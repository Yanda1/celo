from decimal import Decimal

import requests


class Converter:

    def __init__(self, default_end_asset):
        # Get all pairs tickers
        tickers = self.get_ticker()
        self.tickers = {x['symbol']: Decimal(x['price']) for x in tickers}
        # Get all currencies
        self.currency_names = self.currency_names()
        self.end_asset = default_end_asset

    def get_ticker(self):
        try:
            resp = requests.get(
                'https://api.binance.com/api/v3/ticker/price',
                timeout=5
            )
        except requests.exceptions.RequestException:
            return []

        return resp.json()

    def currency_names(self):
        try:
            resp = requests.get(
                'https://api.binance.com/api/v3/exchangeInfo',
                timeout=5
            )
        except requests.exceptions.RequestException:
            return []

        assets = resp.json()

        base_assets = []
        quote_assets = []

        for symbol in assets['symbols']:
            base_assets.append(symbol['baseAsset'])
            quote_assets.append(symbol['quoteAsset'])

        base_assets = list(set(base_assets))
        quote_assets = list(set(quote_assets))

        result = base_assets + quote_assets

        return list(set(result))

    def __single_convert(self, amount, asset, endasset):
        if self.tickers.get(asset + endasset):
            return amount * self.tickers[asset + endasset]
        elif self.tickers.get(endasset + asset):
            return amount / self.tickers[endasset + asset]

        return None

    def __double_convert(self, amount, asset, endasset, currencies=None):
        if not currencies:
            currencies = self.currency_names

        for currency in currencies:
            temp_amount = self.__single_convert(amount, asset, currency)
            if temp_amount:
                result = self.__single_convert(temp_amount, currency, endasset)
                if result:
                    return result
        return None

    def convert(self, amount, asset, end_asset=None, fee=None):
        if not end_asset:
            end_asset = self.end_asset

        if asset == end_asset:
            if fee:
                return amount, amount
            else:
                return amount

        converted_amount = self.__single_convert(amount, asset, end_asset)

        if not converted_amount:
            # Balance can't be converted straight, try to convert in intermediate currency
            converted_amount = self.__double_convert(
                amount,
                asset,
                end_asset,
                ['USDT', 'BTC', 'ETH', 'BNB', 'BUSD'],
            )
            if not converted_amount:
                # Balance can't be converted into the one of intermediate currencies
                # Try to convert in any currency as intermediate
                converted_amount = self.__double_convert(
                    amount,
                    asset,
                    end_asset
                )
            if converted_amount:
                if fee:
                    return converted_amount, converted_amount * (1 - fee * 2)
                else:
                    return converted_amount
        else:
            if fee:
                return converted_amount, converted_amount * (1 - fee)
            else:
                return converted_amount
