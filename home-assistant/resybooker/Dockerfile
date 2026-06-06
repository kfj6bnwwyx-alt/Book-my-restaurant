# Home Assistant local add-on image for ResyBooker.
# Builds the server straight from the GitHub repo so the add-on folder stays tiny
# and tracks main. Rebuild the add-on in HA to pull the latest code.
FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

ARG REPO=https://github.com/kfj6bnwwyx-alt/Book-my-restaurant
ARG REF=main
RUN git clone --depth 1 --branch "$REF" "$REPO" /src

WORKDIR /src/server
RUN pip install --no-cache-dir -r requirements.txt

# Bridge HA add-on options (/data/options.json) to the env vars the app reads,
# and keep the SQLite DB on the add-on's persistent /data volume.
COPY run.py /run.py
CMD ["python", "/run.py"]
