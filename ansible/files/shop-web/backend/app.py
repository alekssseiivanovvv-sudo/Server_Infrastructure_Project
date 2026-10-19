import os
import io
import uuid
import psycopg2
import boto3
from botocore.client import Config
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename

app = Flask(__name__)

# БД берется из переменных окружения (зададим в docker-compose)
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME', 'shopdb')
DB_USER = os.getenv('DB_USER', 'appuser')
DB_PASS = os.getenv('DB_PASS', 'strongpassword')
DB_PORT = int(os.getenv('DB_PORT', '5432'))

GARAGE_ENDPOINT = os.getenv('GARAGE_ENDPOINT')
GARAGE_ACCESS_KEY = os.getenv('GARAGE_ACCESS_KEY')
GARAGE_SECRET_KEY = os.getenv('GARAGE_SECRET_KEY')
GARAGE_BUCKET = os.getenv('GARAGE_BUCKET', 'product-images')
GARAGE_REGION = os.getenv('GARAGE_REGION', 'garage')

def get_db():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, database=DB_NAME,
        user=DB_USER, password=DB_PASS
    )

def get_s3_client():
    return boto3.client(
        's3',
        endpoint_url=GARAGE_ENDPOINT,
        aws_access_key_id=GARAGE_ACCESS_KEY,
        aws_secret_access_key=GARAGE_SECRET_KEY,
        config=Config(
            signature_version='s3v4',
            s3={'addressing_style': 'path'},
            connect_timeout=5,
            read_timeout=15,
            retries={'max_attempts': 2},
        ),
        region_name=GARAGE_REGION
    )

# Инициализация БД (ленивая, т.к. gunicorn не выполняет __main__)
_db_initialized = False

@app.before_request
def _ensure_db():
    global _db_initialized
    if not _db_initialized:
        try:
            conn = get_db()
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS products (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    price NUMERIC(10, 2) NOT NULL,
                    stock INTEGER NOT NULL DEFAULT 0,
                    image_key VARCHAR(512)
                );
            """)
            conn.commit()
            cur.close()
            conn.close()
            _db_initialized = True
        except Exception:
            pass

@app.route('/api/products', methods=['GET'])
def list_products():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT id, name, price, stock, image_key FROM products ORDER BY id;")
    products = [{"id": r[0], "name": r[1], "price": float(r[2]), "stock": r[3], "image_key": r[4]} for r in cur.fetchall()]
    cur.close()
    conn.close()
    return jsonify(products)

@app.route('/api/products', methods=['POST'])
def add_product():
    name = (request.form.get('name') or '').strip()
    price_raw = request.form.get('price', '')
    stock_raw = request.form.get('stock', '')

    if not name: return jsonify({"error": "Name is required"}), 400
    try: price = float(price_raw)
    except: return jsonify({"error": "Price must be a number"}), 400
    if price < 0: return jsonify({"error": "Price must be non-negative"}), 400
    try: stock = int(stock_raw)
    except: return jsonify({"error": "Stock must be an integer"}), 400
    if stock < 0: return jsonify({"error": "Stock must be non-negative"}), 400

    image_key = None
    file = request.files.get('image')
    if file and file.filename:
        safe_name = secure_filename(file.filename)
        ext = os.path.splitext(safe_name)[1].lower()
        if ext not in ('.jpg', '.jpeg', '.png', '.gif', '.webp'):
            return jsonify({"error": "Unsupported image format"}), 400
        image_key = f"{uuid.uuid4().hex}{ext}"
        try:
            s3 = get_s3_client()
            s3.upload_fileobj(io.BytesIO(file.read()), GARAGE_BUCKET, image_key, ExtraArgs={'ContentType': file.mimetype})
        except Exception as e:
            return jsonify({"error": f"Image upload failed: {e}"}), 500

    conn = get_db()
    cur = conn.cursor()
    cur.execute("INSERT INTO products (name, price, stock, image_key) VALUES (%s, %s, %s, %s) RETURNING id;", (name, price, stock, image_key))
    new_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"id": new_id, "image_key": image_key, "status": "created"}), 201

@app.route('/api/buy', methods=['POST'])
def buy_product():
    data = request.get_json(silent=True) or {}
    product_id = data.get('product_id')
    quantity = data.get('quantity')
    if not isinstance(quantity, int) or quantity <= 0: return jsonify({"error": "Quantity must be a positive integer"}), 400
    if not isinstance(product_id, int): return jsonify({"error": "product_id must be an integer"}), 400

    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT stock FROM products WHERE id = %s FOR UPDATE;", (product_id,))
    result = cur.fetchone()
    if not result:
        cur.close(); conn.close()
        return jsonify({"error": "Product not found"}), 404
    current_stock = result[0]
    if current_stock < quantity:
        cur.close(); conn.close()
        return jsonify({"error": f"Only {current_stock} items available"}), 400
    cur.execute("UPDATE products SET stock = stock - %s WHERE id = %s;", (quantity, product_id))
    conn.commit()
    cur.close(); conn.close()
    return jsonify({"status": "success", "remaining": current_stock - quantity})

@app.route('/api/image/<path:key>')
def get_image(key):
    try:
        s3 = get_s3_client()
        response = s3.get_object(Bucket=GARAGE_BUCKET, Key=key)
        return response['Body'].read(), 200, {'Content-Type': response.get('ContentType', 'application/octet-stream')}
    except Exception:
        return jsonify({"error": "Image not found"}), 404

@app.route('/health/live')
def liveness():
    return jsonify({'status': 'ok'}), 200


@app.route('/health')
def readiness():
    checks = {'database': 'ok', 'garage': 'ok'}

    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('SELECT 1;')
        cur.close()
        conn.close()
    except Exception:
        checks['database'] = 'failed'

    try:
        get_s3_client().head_bucket(Bucket=GARAGE_BUCKET)
    except Exception:
        checks['garage'] = 'failed'

    status = 'ok' if all(value == 'ok' for value in checks.values()) else 'failed'
    return jsonify({'status': status, 'checks': checks}), 200 if status == 'ok' else 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
