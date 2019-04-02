FROM golang:1.8.1-stretch

RUN apt-get update
RUN apt-get install -y zip s3cmd
RUN go get -u github.com/jteeuwen/go-bindata/...
ADD . /go/src/github.com/goadapp/goad
WORKDIR /go/src/github.com/goadapp/goad
RUN make linux64

CMD ["/go/src/github.com/goadapp/goad/entrypoint.sh"]
