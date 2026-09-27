FROM ubuntu:24.04 AS build-php
FROM ubuntu:22.04 AS build-pocketmine
FROM build-pocketmine AS final
