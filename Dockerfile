ARG NGINX_VERSION=1.17.10
ARG NGINX_RTMP_VERSION=1.2.1
ARG FFMPEG_VERSION=4.2.2
ARG NASM_VERSION=2.14.02
ARG NVCODEC_VERSION=9.0.18.3

FROM nvidia/cuda:10.2-devel-ubuntu18.04 as ffmpeg
ARG NASM_VERSION
ARG NVCODEC_VERSION
ARG FFMPEG_VERSION

RUN apt-get update && apt-get install -y autoconf \
  curl \
  git \
  pkg-config \
  automake \
  build-essential \
  cmake \
  git-core \
  libass-dev \
  libfreetype6-dev \
  libsdl2-dev \
  libtool \
  libva-dev \
  libvdpau-dev \
  libvorbis-dev \
  libxcb1-dev \
  libxcb-shm0-dev \
  libxcb-xfixes0-dev \
  pkg-config \
  texinfo \
  wget \
  zlib1g-dev \
  libfdk-aac-dev \
  libmp3lame-dev \
  libopus-dev \
  libtheora-dev \
  libwebp-dev \
  libvpx-dev \
  libx264-dev \
  libx265-dev \
  gettext-base

RUN curl -fsSLO https://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.bz2 \
  && tar -xjf nasm-$NASM_VERSION.tar.bz2 \
  && cd nasm-$NASM_VERSION \
  && ./autogen.sh \
  && ./configure \
  && make -j$(nproc) \
  && make install && make distclean

RUN git clone -b n$NVCODEC_VERSION --depth 1 https://git.videolan.org/git/ffmpeg/nv-codec-headers \
  && cd nv-codec-headers \
  && make install

ENV PKG_CONFIG_PATH /usr/local/lib/pkgconfig
RUN curl -fsSLO https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2 \
  && tar -xjf ffmpeg-$FFMPEG_VERSION.tar.bz2 \
  && cd ffmpeg-$FFMPEG_VERSION \
  && ./configure \
    --enable-nvenc \
    --enable-version3 \
    --enable-gpl \
    --enable-nonfree \
    --enable-small \
    --enable-libmp3lame \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libopus \
    --enable-libfdk-aac \
    --enable-libass \
    --enable-libwebp \
    --enable-postproc \
    --enable-avresample \
    --enable-libfreetype \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --extra-libs="-lpthread -lm" \
  && make -j$(nproc) \
  && make install

FROM nvidia/cuda:10.2-devel-ubuntu18.04 as nginx
ARG NGINX_VERSION
ARG NGINX_RTMP_VERSION

RUN apt-get update && apt-get install -y autoconf \
  curl \
  git \
  pkg-config \
  automake \
  build-essential \
  cmake \
  libssl-dev \
  wget \
  libpcre3 \
  libpcre3-dev \
  zlib1g-dev

RUN cd /tmp && \
  wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz

RUN cd /tmp && \
  wget https://github.com/arut/nginx-rtmp-module/archive/v${NGINX_RTMP_VERSION}.tar.gz && \
  tar zxf v${NGINX_RTMP_VERSION}.tar.gz && rm v${NGINX_RTMP_VERSION}.tar.gz

# Compile nginx with nginx-rtmp module.
RUN cd /tmp/nginx-${NGINX_VERSION} && \
  ./configure \
  --prefix=/usr/local/nginx \
  --add-module=/tmp/nginx-rtmp-module-${NGINX_RTMP_VERSION} \
  --conf-path=/etc/nginx/nginx.conf \
  --with-threads \
  --with-file-aio \
  --with-http_ssl_module \
  --with-debug \
  --with-cc-opt="-Wimplicit-fallthrough=0" && \
  cd /tmp/nginx-${NGINX_VERSION} && make && make install

FROM ffmpeg
ENV HTTP_PORT 80
ENV HTTPS_PORT 443
ENV RTMP_PORT 1935

RUN apt-get update && apt-get install -y

ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES compute,video,utility

COPY --from=nginx /usr/local/nginx /usr/local/nginx
COPY --from=nginx /etc/nginx /etc/nginx

ENV PATH "${PATH}:/usr/local/nginx/sbin"
ADD nginx.conf /etc/nginx/nginx.conf.template
RUN mkdir -p /opt/data/hls && mkdir /www
#RUN ln -s /usr/local/cuda-10.2/compat/libcuda.so /usr/local/lib/libcuda.so.1
ENV LD_LIBRARY_PATH "${LD_LIBRARY_PATH}:/usr/local/cuda-10.2/compat"
EXPOSE 1935
EXPOSE 80

CMD envsubst "$(env | sed -e 's/=.*//' -e 's/^/\$/g')" < \
  /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && \
  nginx
