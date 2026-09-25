FROM savonet/liquidsoap:v2.2.4

USER root
RUN mkdir -p /var/quran_yutla/fallback && chown -R liquidsoap:liquidsoap /var/quran_yutla
COPY radio.liq /etc/liquidsoap/radio.liq

USER liquidsoap
EXPOSE 1234
CMD ["liquidsoap", "/etc/liquidsoap/radio.liq"]
