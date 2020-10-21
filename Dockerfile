FROM python:3.6-stretch
ENV LANG C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        nfs-common \
        jq \
        xfsprogs \
    && rm -rf /var/lib/apt/lists/*


COPY . /wd
RUN pip install -r /wd/requirements.txt

WORKDIR /wd
ENTRYPOINT [ "bash", "./startup.sh" ]