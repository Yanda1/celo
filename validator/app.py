import os
import sys
import signal
from threading import Thread, Event
import json
import time
from decimal import Decimal

from celo_sdk.kit import Kit

NETWORK = "https://alfajores-forno.celo-testnet.org"
CONTRACT_ADDR = "0xeF84aF1665e848045e3E3611444B4ee1B3daaa8e"
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
        print('\tNew event: ', event)
        active_account = self.kit.wallet.active_account.address
        # Check that account address is in the validators list
        has_permission = self.contract.functions.validators(active_account).call()

        if has_permission:
            is_valid = True
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
    print('Validator started and waiting for events...')
