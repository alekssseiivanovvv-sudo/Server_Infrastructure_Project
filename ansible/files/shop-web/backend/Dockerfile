FROM python:3.12-alpine

# Для psycopg2 на Alpine нужны компиляторы и библиотеки
RUN apk add --no-cache gcc musl-dev postgresql-dev

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app:app"]
