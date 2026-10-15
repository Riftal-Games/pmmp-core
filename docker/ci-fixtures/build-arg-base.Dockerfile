ARG BASE_IMAGE=ubuntu:22.04
FROM ubuntu:24.04 AS build-php
FROM ${BASE_IMAGE} AS build-pocketmine
FROM build-pocketmine AS final
