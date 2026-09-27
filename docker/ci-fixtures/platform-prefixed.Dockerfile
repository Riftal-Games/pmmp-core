FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS build-php
FROM ubuntu:24.04 AS build-pocketmine
FROM --platform=$BUILDPLATFORM build-pocketmine AS final
