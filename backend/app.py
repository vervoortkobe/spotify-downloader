from __future__ import annotations

import os
import sys
from pathlib import Path

from flask import Flask
from flask_cors import CORS
from dotenv import load_dotenv

load_dotenv()

ROOT = Path(__file__).resolve().parent.parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def create_app():
    app = Flask(__name__)

    frontend_urls = os.environ.get(
        "FRONTEND_URL",
        "http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001"
    )
    allowed_origins = [url.strip() for url in frontend_urls.split(",") if url.strip()]
    CORS(app, origins=allowed_origins)

    from routes import routes
    app.register_blueprint(routes)

    return app


app = create_app()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)
