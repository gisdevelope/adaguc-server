FROM centos/devtoolset-7-toolchain-centos7:7
USER root

MAINTAINER Adaguc Team at KNMI <adaguc@knmi.nl>

######### First stage (build) ############

# production packages, same as stage two
RUN yum update -y && yum install -y \
    epel-release deltarpm

RUN yum install -y \
    python-lxml \
    cairo \
    curl \
    gd \
    gdal \
    hdf5 \
    libxml2 \
    logrotate \
    postgresql-server \
    proj \
    tomcat \
    udunits2 \
    openssl \
    netcdf

# building / development packages
RUN yum update -y && yum clean all
RUN yum install -y centos-release-scl && yum install -y devtoolset-7-gcc-c++ && source /opt/rh/devtoolset-7/enable
RUN yum install -y \
    cairo-devel \
    curl-devel \
    gd-devel \
    gdal-devel \
    hdf5-devel \
    libxml2-devel \
    make \
    netcdf-devel \
    openssl \
    postgresql-devel \
    proj-devel \
    sqlite-devel \
    udunits2-devel 

# Install adaguc-server from context
WORKDIR /adaguc
COPY . /adaguc/adaguc-server-master

# Alternatively install adaguc from github
# WORKDIR /adaguc
# ADD https://github.com/KNMI/adaguc-server/archive/master.tar.gz /adaguc/adaguc-server-master.tar.gz
# RUN tar -xzvf adaguc-server-master.tar.gz

WORKDIR /adaguc/adaguc-server-master
RUN bash compile.sh

######### Second stage (production) ############
FROM centos:7

# production packages, same as stage one
RUN yum update -y && yum install -y \
    epel-release deltarpm

RUN yum install -y \
    python-lxml \
    cairo \
    curl \
    gd \
    gdal \
    hdf5 \
    libxml2 \
    logrotate \
    postgresql-server \
    proj \
    tomcat \
    udunits2 \
    openssl \
    netcdf

WORKDIR /adaguc/adaguc-server-master

# Install adaguc-services (spring boot application for running adaguc-server)
RUN curl -L https://jitpack.io/com/github/KNMI/adaguc-services/1.0.5/adaguc-services-1.0.5.war > /usr/share/tomcat/webapps/adaguc-services.war
   
# Install compiled adaguc binaries from stage one    
COPY --from=0 /adaguc/adaguc-server-master/bin /adaguc/adaguc-server-master/bin
COPY --from=0 /adaguc/adaguc-server-master/data /adaguc/adaguc-server-master/data
COPY --from=0 /adaguc/adaguc-server-master/tests /adaguc/adaguc-server-master/tests
COPY --from=0 /adaguc/adaguc-server-master/runtests.sh /adaguc/adaguc-server-master/runtests.sh

# Run adaguc-server functional tests
RUN bash runtests.sh

# Setup directories
RUN mkdir -p /data/adaguc-autowms && \
    mkdir -p /data/adaguc-datasets && \
    mkdir -p /data/adaguc-data && \
    mkdir -p /adaguc/userworkspace && \
    mkdir -p /data/adaguc-services-home && \
    mkdir -p /adaguc/basedir && \
    mkdir -p /var/log/adaguc && \
    mkdir -p /adaguc/adagucdb && \
    mkdir -p /adaguc/security && \
    mkdir -p /data/adaguc-datasets-internal && \
    mkdir -p /servicehealth
    
# Configure
COPY ./Docker/adaguc-server-config.xml /adaguc/adaguc-server-config.xml
COPY ./Docker/adaguc-services-config.xml /adaguc/adaguc-services-config.xml
COPY ./Docker/start.sh /adaguc/
COPY ./Docker/adaguc-server-logrotate /etc/logrotate.d/adaguc
COPY ./Docker/adaguc-server-*.sh /adaguc/
COPY ./Docker/baselayers.xml /data/adaguc-datasets-internal/baselayers.xml
COPY ./Docker/tomcat-server.xml /etc/tomcat/server.xml
RUN  chmod +x /adaguc/adaguc-server-*.sh && chmod +x /adaguc/start.sh

# Set adaguc-services configuration file
ENV ADAGUC_SERVICES_CONFIG=/adaguc/adaguc-services-config.xml 
ENV ADAGUCDB=/adaguc/adagucdb
ENV EXTERNALADDRESS="http://localhost:8080/"

# These volumes are configured in /adaguc/adaguc-server-config.xml
# Place your netcdfs, HDF5 and GeoJSONS here, they will be visualized with the source=<file> KVP via the URI
VOLUME /data/adaguc-autowms   
# Place your dataset XML configuration here, they will be accessible with the dataset=<dataset basename> KVP via the URI
VOLUME /data/adaguc-datasets  
# Place your netcdfs, HDF5 and GeoJSONS here you don't want to have accessible via dataset configurations.
VOLUME /data/adaguc-data      
# Loggings are save here, including logrotate
VOLUME /var/log/adaguc/       
# You can make the postgresql database persistent by externally mounting it. Database will be initialized if directory is empty.
VOLUME /adaguc/adagucdb       
# Settings for HTTPS / SSL can be set via keystore and truststore. Self signed cert will be created if nothing is provided.
VOLUME /adaguc/security

# For HTTP
EXPOSE 8080 
# For HTTPS
EXPOSE 8443 

ENTRYPOINT /adaguc/start.sh