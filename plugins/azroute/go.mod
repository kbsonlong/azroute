module coredns-plugins/plugins/azroute

go 1.21

replace coredns-plugins/plugins/common => ../common

require (
	coredns-plugins/plugins/common v0.0.0-00010101000000-000000000000
	github.com/coredns/caddy v1.1.1
	github.com/coredns/coredns v1.11.1
	github.com/hashicorp/golang-lru v1.0.2
	github.com/miekg/dns v1.1.55
	github.com/yl2chen/cidranger v1.0.2
)

require (
	github.com/apparentlymart/go-cidr v1.1.0 // indirect
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/cespare/xxhash/v2 v2.2.0 // indirect
	github.com/flynn/go-shlex v0.0.0-20150515145356-3f9db97f8568 // indirect
	github.com/go-task/slim-sprig v0.0.0-20230315185526-52ccab3ef572 // indirect
	github.com/golang/mock v1.6.0 // indirect
	github.com/golang/protobuf v1.5.3 // indirect
	github.com/google/pprof v0.0.0-20230509042627-b1315fad0c5a // indirect
	github.com/grpc-ecosystem/grpc-opentracing v0.0.0-20180507213350-8e809c8a8645 // indirect
	github.com/matttproud/golang_protobuf_extensions v1.0.4 // indirect
	github.com/onsi/ginkgo/v2 v2.11.0 // indirect
	github.com/opentracing/opentracing-go v1.2.0 // indirect
	github.com/prometheus/client_golang v1.16.0 // indirect
	github.com/prometheus/client_model v0.4.0 // indirect
	github.com/prometheus/common v0.44.0 // indirect
	github.com/prometheus/procfs v0.10.1 // indirect
	github.com/quic-go/qtls-go1-20 v0.3.1 // indirect
	github.com/quic-go/quic-go v0.37.4 // indirect
	golang.org/x/crypto v0.12.0 // indirect
	golang.org/x/exp v0.0.0-20221205204356-47842c84f3db // indirect
	golang.org/x/mod v0.10.0 // indirect
	golang.org/x/net v0.14.0 // indirect
	golang.org/x/sys v0.11.0 // indirect
	golang.org/x/text v0.12.0 // indirect
	golang.org/x/tools v0.9.3 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20230807174057-1744710a1577 // indirect
	google.golang.org/grpc v1.57.0 // indirect
	google.golang.org/protobuf v1.31.0 // indirect
)
