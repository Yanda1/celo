from decimal import Decimal


NETWORK = "https://alfajores-forno.celo-testnet.org"
CONTRACT_ADDR = "0xF82e6a3D0fE40EDdf0Bcf3c4bBe9c0bE795D7Fb7"
CONTRACT_ABI = "YandaToken.json"
SERVICE_ADDR = "0xeB56c1d19855cc0346f437028e6ad09C80128e02"
REFRESH_INTERVAL = 1
RESTART_THRESHOLD = Decimal('1.0')
VERSION = 4     # 0.1.15 == 115 , 0.1.4 == 104
BINANCE_PAIRS_URL = 'https://api.binance.com/api/v3/exchangeInfo'


class Side:
    SELL = 0
    BUY = 1


class Purpose:
    START = 0
    RESTART = 1
    TERMINATE = 2
    CONTINUE = 3
