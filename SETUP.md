# ResyBooker — setup order

Personal reservation app: your saved Google Maps pins, one screen that checks
Resy + OpenTable availability across all of them, one-tap Resy booking.

## 1. Server on the VPS (do this first)

    cd server
    cp .env.example .env
    # APP_KEY: openssl rand -hex 24  (paste same value into iOS Constants.swift)
    # RESY_EMAIL / RESY_PASSWORD: lets the server mint + auto-refresh the token
    # (or paste a RESY_AUTH_TOKEN grabbed from DevTools on resy.com)
    docker compose up -d --build

Front with Caddy for TLS:

    resy.brentbrooks.com {
        reverse_proxy 127.0.0.1:8080
    }

Add an A record for resy.brentbrooks.com -> VPS in Pair Domains DNS.

Find your payment method id once the server is up:

    curl -H "X-App-Key: YOUR_KEY" https://resy.brentbrooks.com/resy/payment-methods

Put the id in .env as RESY_PAYMENT_METHOD_ID, then `docker compose up -d`.

## 2. iOS app

Create a new iOS app in Xcode (iOS 17+, SwiftUI, SwiftData), name it ResyBooker,
then drag the contents of ios/ResyBooker/ into the project preserving the group
structure. Set Constants.swift apiBaseURL and appKey to match the server.

Sideload to your devices with your Apple Developer account. For 3 users an
ad-hoc or developer-signed build is fine; use the paid account for 1-year
signing so you're not re-signing weekly.

## 3. First use

1. Google Takeout > Saved > export your list as GeoJSON.
2. Spots tab > import, paste the GeoJSON.
3. Tap each pin > link to the right Resy (or OpenTable) venue. Score >= 90 green
   is almost always correct; confirm the orange ones.
4. Tables tab > pick date/time/party > Find Tables.
5. Tap a time chip on an available spot > Book.

## Build order if extending

Read availability is proven first (find -> display). Booking is last because it
touches money and breaks most often. Keep token refresh solid before booking:
a stale token is the failure you'll hit most. OpenTable is availability-only by
design; all booking goes through Resy.
