import os
import sys
import signal
from threading import Thread, Event
import json
import time
from decimal import Decimal

from celo_sdk.kit import Kit

NETWORK = "https://alfajores-forno.celo-testnet.org"
CONTRACT_ADDR = "0x2E86B9d8Dd4Aa8228747Dc3A8f7bF6538a300d87"
CONTRACT_ABI = "YandaToken.json"
REFRESH_INTERVAL = 1
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

    def handle_event(self, event):
        print('New event: ', event)
        active_account = self.kit.wallet.active_account.address
        transaction = self.contract.functions.validateTermination(
            event['args']['customer'],
            True
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
    if len(sys.argv) == 1:
        print('\tPrivate key is required for running the validator app, run: '
              'python validator.py <your-key-here>')
        sys.exit()
    watch = EventWatcher(sys.argv[1], stopFlag)
    watch.start()
    print('Validator started and waiting for events...')
