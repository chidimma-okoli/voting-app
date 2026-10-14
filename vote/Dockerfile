# base defines a base stage that uses the official python runtime base image
FROM python:3.11-slim AS base

# Add curl for healthcheck
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Update Python packaging tools to address reported vulnerabilities
RUN python -m pip install --no-cache-dir --upgrade \
    "pip>=26.2.1" \
    "setuptools>=83.0.0" \
    "wheel>=0.46.2" \
    "jaraco.context>=6.1.0"

# Set the application directory
WORKDIR /usr/local/app

# Install our requirements.txt
COPY requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir -r requirements.txt

# dev defines a stage for development, where it'll watch for filesystem changes
FROM base AS dev
RUN python -m pip install --no-cache-dir watchdog
ENV FLASK_ENV=development
CMD ["python", "app.py"]

# Clean production runtime stage
FROM python:3.11-slim AS final

# Add curl for healthchecks
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/app

# Copy application dependencies, excluding build tools
COPY --from=base /usr/local/lib/python3.11/site-packages/ /tmp/python-packages/

# Remove packaging tools and their bundled metadata

RUN rm -rf \
    /tmp/python-packages/pip \
    /tmp/python-packages/pip-*.dist-info \
    /tmp/python-packages/setuptools \
    /tmp/python-packages/setuptools-*.dist-info \
    /tmp/python-packages/wheel \
    /tmp/python-packages/wheel-*.dist-info \
    /tmp/python-packages/jaraco_context-*.dist-info \
    /tmp/python-packages/jaraco/context \
    /usr/local/lib/python3.11/site-packages/setuptools \
    /usr/local/lib/python3.11/site-packages/setuptools-*.dist-info && \
    cp -a /tmp/python-packages/. /usr/local/lib/python3.11/site-packages/ && \
    rm -rf /tmp/python-packages


COPY . .

EXPOSE 80

CMD ["gunicorn", "app:app", "-b", "0.0.0.0:80", "--log-file", "-", "--access-logfile", "-", "--workers", "4", "--keep-alive", "0"]
