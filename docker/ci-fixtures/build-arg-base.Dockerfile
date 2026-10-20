ARG BASE_IMAGE=ubuntu:22.04
FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac AS build-php
FROM ${BASE_IMAGE} AS build-pocketmine
FROM build-pocketmine AS final
