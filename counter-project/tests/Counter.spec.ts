import { Blockchain, type SandboxContract } from '@ton/sandbox';
import { Cell, toNano } from '@ton/core';
import '@ton/test-utils';

import counterBuild from '../build/counter.json';
import { Counter } from '../wrappers/Counter';

describe('Counter', () => {
  let code: Cell;
  let blockchain: Blockchain;
  let counter: SandboxContract<Counter>;

  beforeAll(() => {
    code = Cell.fromBase64(counterBuild.code_boc64);
  });

  beforeEach(async () => {
    blockchain = await Blockchain.create();

    counter = blockchain.openContract(
      Counter.fromStorage(
        {
          id: 0n,
          counter: 0n,
        },
        {
          overrideContractCode: code,
        },
      ),
    );

    const deployer = await blockchain.treasury('deployer');
    const deployResult = await counter.sendDeploy(deployer.getSender(), toNano('0.05'));

    expect(deployResult.transactions).toHaveTransaction({
      from: deployer.address,
      to: counter.address,
      deploy: true,
      success: true,
    });
  });

  it('deploys with zero state', async () => {
    expect(await counter.getCurrentCounter()).toBe(0n);
  });

  it('increments and decrements the counter', async () => {
    const operator = await blockchain.treasury('operator');

    const increaseResult = await counter.sendIncreaseCounter(operator.getSender(), toNano('0.05'), {
      increaseBy: 7n,
    });

    expect(increaseResult.transactions).toHaveTransaction({
      from: operator.address,
      to: counter.address,
      success: true,
    });
    expect(await counter.getCurrentCounter()).toBe(7n);

    const decreaseResult = await counter.sendDecreaseCounter(operator.getSender(), toNano('0.05'), {
      decreaseBy: 2n,
    });

    expect(decreaseResult.transactions).toHaveTransaction({
      from: operator.address,
      to: counter.address,
      success: true,
    });
    expect(await counter.getCurrentCounter()).toBe(5n);
  });
});
