FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart pub global activate dart_frog_cli
RUN dart_frog build
RUN dart compile exe build/bin/server.dart -o /app/server

FROM dart:stable

WORKDIR /app
COPY --from=build /app/server ./server

ENV PORT=10000
EXPOSE 10000
CMD ["./server"]
