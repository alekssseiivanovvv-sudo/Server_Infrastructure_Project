import os
import io
import uuid
import psycopg2
import boto3
from botocore.client import Config
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename

app = Flask(__name__)

# --- Конфигурация БД ---
DB_HOST = os.getenv('DB_HOST', 'pg-primary')
DB_NAME = os.getenv('DB_NAME', 'shopdb')
DB_USER = os.getenv('DB_USER', 'appuser')
DB_PASS = os.getenv('DB_PASS', 'strongpassword')

# --- Конфигурация SeaweedFS S3 ---
SEAWEED_ENDPOINT = os.getenv('SEAWEED_ENDPOINT', 'http://seaweedfs:8333')
SEAWEED_ACCESS_KEY = os.getenv('SEAWEED_ACCESS_KEY', 'any')
SEAWEED_SECRET_KEY = os.getenv('SEAWEED_SECRET_KEY', 'any')
SEAWEED_BUCKET = 'product-images'


def get_db():
    return psycopg2.connect(
        host=DB_HOST, database=DB_NAME,
        user=DB_USER, password=DB_PASS
    )


def get_s3_client():
    return boto3.client(
        's3',
        endpoint_url=SEAWEED_ENDPOINT,
        aws_access_key_id=SEAWEED_ACCESS_KEY,
        aws_secret_access_key=SEAWEED_SECRET_KEY,
        config=Config(signature_version='s3v4'),
        region_name='us-east-1'
    )


def ensure_bucket(s3):
    try:
        s3.head_bucket(Bucket=SEAWEED_BUCKET)
    except Exception:
        s3.create_bucket(Bucket=SEAWEED_BUCKET)


# --- Инициализация схемы БД ---
def init_db():
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

_db_initialized = False

@app.before_request
def _ensure_db():
    global _db_initialized
    if not _db_initialized:
        try:
            init_db()
            _db_initialized = True
        except Exception:
            # Primary может быть ещё не готов — попробуем при следующем запросе
            pass
# --- API ---

@app.route('/api/products', methods=['GET'])
def list_products():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT id, name, price, stock, image_key FROM products ORDER BY id;")
    products = []
    for row in cur.fetchall():
        products.append({
            "id": row[0],
            "name": row[1],
            "price": float(row[2]),
            "stock": row[3],
            "image_key": row[4]
        })
    cur.close()
    conn.close()
    return jsonify(products)


@app.route('/api/products', methods=['POST'])
def add_product():
    """
    Создаёт товар. Принимает multipart/form-data:
      - name    (str, required)
      - price   (float, required)
      - stock   (int, required)
      - image   (file, optional)
    """
    name = (request.form.get('name') or '').strip()
    price_raw = request.form.get('price', '')
    stock_raw = request.form.get('stock', '')

    # --- Валидация ---
    if not name:
        return jsonify({"error": "Name is required"}), 400

    try:
        price = float(price_raw)
    except (TypeError, ValueError):
        return jsonify({"error": "Price must be a number"}), 400
    if price < 0:
        return jsonify({"error": "Price must be non-negative"}), 400

    try:
        stock = int(stock_raw)
    except (TypeError, ValueError):
        return jsonify({"error": "Stock must be an integer"}), 400
    if stock < 0:
        return jsonify({"error": "Stock must be non-negative"}), 400

    # --- Загрузка картинки в SeaweedFS (опционально) ---
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
            ensure_bucket(s3)
            s3.upload_fileobj(
                io.BytesIO(file.read()),
                SEAWEED_BUCKET,
                image_key,
                ExtraArgs={'ContentType': file.mimetype or 'application/octet-stream'}
            )
        except Exception as e:
            return jsonify({"error": f"Image upload failed: {e}"}), 500

    # --- Сохраняем товар в БД ---
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO products (name, price, stock, image_key) VALUES (%s, %s, %s, %s) RETURNING id;",
        (name, price, stock, image_key)
    )
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

    if not isinstance(quantity, int) or quantity <= 0:
        return jsonify({"error": "Quantity must be a positive integer"}), 400
    if not isinstance(product_id, int):
        return jsonify({"error": "product_id must be an integer"}), 400

    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT stock FROM products WHERE id = %s FOR UPDATE;", (product_id,))
    result = cur.fetchone()

    if not result:
        cur.close()
        conn.close()
        return jsonify({"error": "Product not found"}), 404

    current_stock = result[0]
    if current_stock < quantity:
        cur.close()
        conn.close()
        return jsonify({"error": f"Only {current_stock} items available"}), 400

    cur.execute("UPDATE products SET stock = stock - %s WHERE id = %s;",
                (quantity, product_id))
    conn.commit()
    cur.close()
    conn.close()

    return jsonify({"status": "success", "remaining": current_stock - quantity})


@app.route('/api/image/<path:key>')
def get_image(key):
    """Отдаёт картинку из SeaweedFS."""
    try:
        s3 = get_s3_client()
        response = s3.get_object(Bucket=SEAWEED_BUCKET, Key=key)
        data = response['Body'].read()
        content_type = response.get('ContentType', 'application/octet-stream')
        return data, 200, {'Content-Type': content_type}
    except Exception:
        return jsonify({"error": "Image not found"}), 404


# Инициализируем БД при старте (retry на случай, если Primary ещё не готов)
if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
