FROM busybox

ENV HOME=/opt/app-root/src \
    LOG_INTERVAL=5

ADD log_script.sh ${HOME}/

RUN chmod a+x ${HOME}/log_script.sh

WORKDIR ${HOME}

USER nobody

CMD ["./log_script.sh"]
