FROM registry.access.redhat.com/ubi8/ubi:8.5-214

WORKDIR ~

RUN yum install -y unzip
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN ./aws/install

RUN curl https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz -o "oc.tar.gz"
RUN tar xzf oc.tar.gz
RUN mv oc /usr/local/bin/oc

RUN curl "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux32" -o "jq"
RUN mv jq /usr/local/bin/jq

RUN rm oc.tar.gz awscliv2.zip

RUN mkdir -p ~/.aws
COPY delegation-record.json delegation-record.json
COPY main.sh main.sh
RUN chmod +x main.sh

CMD ["./main.sh"]