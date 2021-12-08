import os
import sys
import signal
from threading import Thread, Event
import json
import time
import math
from decimal import Decimal, ROUND_DOWN

import requests
from celo_sdk.kit import Kit

from constants import (
    NETWORK, CONTRACT_ADDR, CONTRACT_ABI, SERVICE_ADDR, REFRESH_INTERVAL, RESTART_THRESHOLD,
    VERSION, BINANCE_PAIRS_URL,
    Side, Purpose,
)

stopFlag = Event()


def init(private_key):
    kit = Kit(NETWORK)
    kit.wallet_add_new_key = private_key

    accounts = kit.wallet.accounts
    accounts_addr = list(accounts.keys())
    # Set second account as current
    kit.wallet_change_account = accounts_addr[1]

    # Load contract abi
    with open(CONTRACT_ABI, 'r') as fp:
        contract_data = json.load(fp)

    # Get contract interface
    contract = kit.w3.eth.contract(
        address=CONTRACT_ADDR,
        abi=json.dumps(contract_data['abi'])
    )

    return kit, contract


def exit_handler(signal, frame):
    stopFlag.set()
    time.sleep(REFRESH_INTERVAL * 2)
    os._exit(0)


class EventWatcher(Thread):
    def __init__(self, private_key, stop):
        Thread.__init__(self)
        self.private_key = private_key
        self.kit, self.contract = init(private_key)
        self.stopped = stop
        self.latest_block = None

    @staticmethod
    def deserialize_order(order_str):
        order_dict = json.loads(order_str)
        result = {
            'id': order_dict['id'],
            'price': Decimal(order_dict['p']),
            'size_sent': Decimal(order_dict['ss']),
            'size_received': Decimal(order_dict['sr']),
            'side': order_dict['sd'],
            'status': order_dict['st'],
            'purpose': order_dict['pr'],
            'order_type': order_dict['ot'],
            'update_time': order_dict['ut'],
        }
        return result

    def get_pair(self, pair_name):
        data = None
        try:
            response = requests.get(url=BINANCE_PAIRS_URL, params={'symbol': pair_name})
            if response.status_code == 200:
                data = response.json()['symbols'][0]
            else:
                response.raise_for_status()
        except requests.exceptions.RequestException:
            print('Get pair failed, retrying...')
            time.sleep(2)
            return self.get_pair(pair_name)

        return data

    @staticmethod
    def get_decimal_precision(decimal_var):
        if type(decimal_var) is not Decimal:
            raise TypeError('First argument must be a Decimal type object.')

        max_precision = int(math.fabs(decimal_var.as_tuple().exponent))
        for x in range(0, max_precision + 1):
            tail, integer = math.modf(decimal_var * 10 ** x)
            if tail == 0.0:
                return x

    @staticmethod
    def round_down(number, decimals=0):
        number_str = str(number)
        rounded_decimal = Decimal(number_str).quantize(
            Decimal((0, (1,), -decimals)),
            rounding=ROUND_DOWN
        )
        return rounded_decimal

    @staticmethod
    def find_oposit_order(order, prev_orders):
        result = prev_orders[0]

        for idx in range(len(prev_orders)-1, -1, -1):
            if prev_orders[idx]['purpose'] == Purpose.RESTART:
                result = prev_orders[idx]
                break
            elif order['side'] == Side.BUY and prev_orders[idx]['side'] == Side.SELL:
                digits = abs(prev_orders[idx]['size_sent'].as_tuple().exponent)
                if self.round_down(order['size_sent'], digits) == prev_orders[idx]['size_sent']:
                    result = prev_orders[idx]
                    break
            elif order['side'] == Side.SELL and prev_orders[idx]['side'] == Side.BUY:
                digits = abs(order['size_sent'].as_tuple().exponent)
                if self.round_down(prev_orders[idx]['size_sent'], digits) == order[idx]['size_sent']:
                    result = prev_orders[idx]
                    break

        return result

    def validate_bot(self, customer_address, bot_id):
        process = self.contract.functions.processes(
            customer_address,
            bot_id
        ).call()
        print('\tProcess: ', process)
        bot = json.loads(process[4])
        print('\tBot: ', bot)
        actions = self.contract.events.Action.getLogs(
            fromBlock=0,
            argument_filters={'productId': bot_id}
        )
        if len(actions) == 0:
            # Refund if bot made 0 filled orders
            return False

        pair_data = self.get_pair(bot['p'])
        size_precision = self.get_decimal_precision(Decimal(pair_data['filters'][2]['stepSize']))

        result = True
        orders = []
        for action in actions:
            order = self.deserialize_order(action['args']['data'])
            if order['purpose'] == Purpose.CONTINUE:
                # If order purpose is CONTINUE
                if len(orders) < 3:
                    oposit_order = orders[0]
                else:
                    oposit_order = self.find_oposit_order(order, orders)

                oposit_size_sent = self.round_down(oposit_order['size_received'], size_precision) \
                    / oposit_order['price']
                oposit_size_received = self.round_down(oposit_order['size_sent'], size_precision) \
                    * oposit_order['price']

                if(order['side'] == Side.BUY and
                   order['size_sent'] < oposit_size_sent):
                    # If we bought less than in the previous SELL order, invalid
                    result = False
                    print('we bought less than in the previous SELL order, invalid')
                elif(order['side'] == Side.SELL and
                     order['size_received'] < oposit_size_received):
                    # If on SELL we received less quote than in the previous BUY order, invalid
                    result = False
                    print('on SELL we received less quote than in the previous BUY order, invalid')
            elif order['purpose'] == Purpose.RESTART:
                previous_order = orders[-1]
                price_deviation = 0
                if order['side'] == Side.BUY:
                    price_deviation = abs(
                        (abs(order['price'] - previous_order['price']) / previous_order['price'])
                        - bot['rq']
                    )
                else:
                    price_deviation = abs(
                        (abs(order['price'] - previous_order['price']) / previous_order['price'])
                        - bot['rb']
                    )

                if price_deviation > RESTART_THRESHOLD:
                    result = False

            orders.append(order)

        return result

    def handle_event(self, event):
        print('New event: ', event)
        active_account = self.kit.wallet.active_account.address
        # Is this validator address ever requested to validate?
        validation_requests = self.contract.functions.validators(active_account).call()[0]
        # Get required version for validating current service
        reqired_version = self.contract.functions.services(SERVICE_ADDR).call()[2]

        if validation_requests > 0 and reqired_version <= VERSION:
            is_valid = self.validate_bot(event['args']['customer'], event['args']['productId'])
            print(f'\tValidated with "{is_valid}"')
            transaction = self.contract.functions.validateTermination(
                event['args']['customer'],
                event['args']['productId'],
                is_valid
            ).buildTransaction({
                'gas': 250000,
                'gasPrice': self.kit.w3.toWei(Decimal('1'), 'gwei'),
                'from': active_account,
                'nonce': self.kit.w3.eth.getTransactionCount(active_account)
            })
            signed_txn = self.kit.w3.eth.account.signTransaction(
                transaction,
                private_key=self.private_key
            )
            self.kit.w3.eth.sendRawTransaction(signed_txn.rawTransaction)
        else:
            print('\tYour account address is not permitted to validate.')

    def run(self):
        terminate = self.contract.events.Terminate
        while not self.stopped.wait(REFRESH_INTERVAL):
            if self.latest_block:
                for event in terminate.getLogs(fromBlock=self.latest_block + 1):
                    self.handle_event(event)
                    self.latest_block = event['blockNumber']
            else:
                for event in terminate.getLogs(fromBlock='latest'):
                    self.handle_event(event)
                    self.latest_block = event['blockNumber']
        sys.exit()


if __name__ == '__main__':
    signal.signal(signal.SIGINT, exit_handler)
    private_key = os.getenv('PRIVATE_KEY', None)
    if private_key is None:
        print('\tPrivate key is required in order to start validator app, '
              'please add "PRIVATE_KEY" environment variable.')
        sys.exit()
    watch = EventWatcher(private_key, stopFlag)
    watch.start()
    print(f'Validator({VERSION}) started and waiting for events...')
