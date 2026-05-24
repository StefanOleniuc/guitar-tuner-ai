# Imagine Docker pentru deployment pe Railway.
#
# Folosim python:3.11-slim ca bază (mai mic decat full, dar are toate
# pachetele de sistem necesare pentru TensorFlow/CREPE).
FROM python:3.11-slim

WORKDIR /app

# CREPE / hmmlearn necesită setuptools<81 din cauza unei API-uri vechi
# eliminate. Îl instalăm înainte de orice ca să nu fie suprascris.
# `--no-build-isolation` la pasul următor garantează că pip folosește
# acest setuptools în loc să creeze un environment izolat cu unul nou.
RUN pip install --no-cache-dir "setuptools<81" wheel

COPY requirements.txt .
RUN pip install --no-cache-dir --no-build-isolation -r requirements.txt

COPY . .

EXPOSE 8000

# Pornim Uvicorn ASGI server (FastAPI rulează peste el).
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
