FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
# A new named volume copies ownership from the image, so /data becomes writable for nobody.
RUN mkdir /data && chown nobody /data
USER nobody
EXPOSE 8000
CMD ["python", "-u", "app.py"]
