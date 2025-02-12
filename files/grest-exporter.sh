#!/bin/bash
/usr/bin/socat TCP-LISTEN:8059,reuseaddr,fork SYSTEM:"echo HTTP/1.1 200 OK;SERVED=true bash /usr/local/bin/koios/get-metrics.sh;"
