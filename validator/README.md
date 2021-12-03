# Validator App

This app is made for validation purposes to satisfy the Yanda defi ecosystem.

### Env variables:

- PRIVATE_KEY (required) - your wallet private key on Alfajores Testnet account

### App start:

Open your favorite Terminal and run these commands:

1. Build docker image:
```sh
> docker build -t dev-validator:latest .
```

2. Start app with python:
```sh
> docker run --env PRIVATE_KEY=<your-private-key> dev-validator
```
