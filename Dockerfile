FROM crystallang/crystal:1.7.2-alpine AS dev

RUN apk --update --no-cache add \
  bash

WORKDIR /app/

# COPY ./shard.yml ./shard.lock /app/

# RUN shards install --frozen

COPY ./src/ /app/src/
# COPY Makefile /app/

# RUN make

ENV CRYSTAL_LOAD_DEBUG_INFO=0

CMD ["/bin/sh"]
