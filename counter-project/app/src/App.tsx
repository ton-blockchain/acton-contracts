import { useDeferredValue, useMemo, useState } from 'react';
import {
  TonConnectButton,
  useAddress,
  useBalance,
  useNetwork,
  useSendTransaction,
} from '@ton/appkit-react';

import {
  buildCounterActionTransaction,
  buildDeployTransaction,
  DEFAULT_COUNTER_ID,
  DEFAULT_DEPLOY_VALUE,
  DEFAULT_MESSAGE_VALUE,
  DEFAULT_STEP,
  getCounterPreview,
  getErrorMessage,
  isCounterDeployed,
  normalizeCounterAddress,
  readCounter,
} from './lib/counter';
import { TON_NETWORK, TON_NETWORK_LABEL, TONVIEWER_URL } from './lib/ton';

type PendingAction = 'deploy' | 'increase' | 'decrease' | 'fetch' | null;

interface CounterValueState {
  status: 'idle' | 'loading' | 'ready' | 'missing' | 'error';
  value: bigint | null;
  message: string;
  fetchedAt: string | null;
}

const initialCounterValueState: CounterValueState = {
  status: 'idle',
  value: null,
  message: 'Enter a counter address and fetch the current value.',
  fetchedAt: null,
};

export default function App() {
  const walletAddress = useAddress();
  const walletBalance = useBalance();
  const walletNetwork = useNetwork();

  const [counterId, setCounterId] = useState(DEFAULT_COUNTER_ID);
  const deferredCounterId = useDeferredValue(counterId);

  const [counterAddress, setCounterAddress] = useState('');
  const [step, setStep] = useState(DEFAULT_STEP);

  const [deployValue, setDeployValue] = useState(DEFAULT_DEPLOY_VALUE);
  const [messageValue, setMessageValue] = useState(DEFAULT_MESSAGE_VALUE);
  const [pendingAction, setPendingAction] = useState<PendingAction>(null);

  const [statusMessage, setStatusMessage] = useState(
    'Connect a wallet, deploy a counter, then interact with it.',
  );
  const [counterValue, setCounterValue] = useState<CounterValueState>(
    initialCounterValueState,
  );

  const preview = useMemo(() => {
    try {
      return {
        value: getCounterPreview(deferredCounterId),
        error: null,
      };
    } catch (error) {
      return {
        value: null,
        error: getErrorMessage(error),
      };
    }
  }, [deferredCounterId]);

  const { mutateAsync: sendTransaction, isPending: isWalletPromptOpen } =
    useSendTransaction();
  const walletReady = Boolean(walletAddress);
  const walletNetworkMismatch =
    walletNetwork !== undefined &&
    walletNetwork.chainId !== TON_NETWORK.chainId;
  const busy = pendingAction !== null || isWalletPromptOpen;

  async function fetchCounter(addressValue: string) {
    const snapshot = await readCounter(addressValue);

    setCounterAddress(snapshot.address);
    setCounterValue({
      status: snapshot.isDeployed ? 'ready' : 'missing',
      value: snapshot.value,
      message: snapshot.isDeployed
        ? 'Latest value loaded from chain.'
        : 'This address is not deployed on the selected network yet.',
      fetchedAt: new Date().toLocaleTimeString(),
    });
  }

  async function handleDeploy() {
    if (!walletReady) {
      setStatusMessage('Connect a wallet before deploying a counter.');
      return;
    }

    if (preview.error || !preview.value) {
      setStatusMessage(preview.error ?? 'Counter ID is invalid.');
      return;
    }

    setPendingAction('deploy');

    try {
      const deployment = buildDeployTransaction(counterId, deployValue);
      const alreadyDeployed = await isCounterDeployed(
        deployment.preview.contract.address,
      );

      if (alreadyDeployed) {
        setCounterAddress(deployment.address);
        setStatusMessage(
          `Counter ${counterId} is already deployed at ${deployment.address}.`,
        );
        return;
      }

      await sendTransaction(deployment.request);
      setCounterAddress(deployment.address);
      setCounterValue(initialCounterValueState);
      setStatusMessage(
        `Deployment request sent. After the transaction lands, fetch the value for ${deployment.address}.`,
      );
    } catch (error) {
      setStatusMessage(getErrorMessage(error));
    } finally {
      setPendingAction(null);
    }
  }

  async function handleAction(action: 'increase' | 'decrease') {
    if (!walletReady) {
      setStatusMessage('Connect a wallet before sending contract messages.');
      return;
    }

    setPendingAction(action);

    try {
      const transaction = buildCounterActionTransaction({
        action,
        addressValue: counterAddress,
        messageValue,
        stepValue: step,
      });

      await sendTransaction(transaction.request);
      setCounterAddress(transaction.address);
      setStatusMessage(
        `${action === 'increase' ? 'Increase' : 'Decrease'} request sent. Fetch the latest value after confirmation.`,
      );
    } catch (error) {
      setStatusMessage(getErrorMessage(error));
    } finally {
      setPendingAction(null);
    }
  }

  async function handleFetch() {
    if (!counterAddress.trim()) {
      setStatusMessage('Provide a counter address first.');
      return;
    }

    setPendingAction('fetch');
    setCounterValue((current) => ({
      ...current,
      status: 'loading',
      message: 'Reading contract state...',
    }));

    try {
      await fetchCounter(counterAddress);
      setStatusMessage('Counter state refreshed from chain.');
    } catch (error) {
      const message = getErrorMessage(error);
      setCounterValue({
        status: 'error',
        value: null,
        message,
        fetchedAt: null,
      });
      setStatusMessage(message);
    } finally {
      setPendingAction(null);
    }
  }

  function handleUsePreviewAddress() {
    if (!preview.value) {
      return;
    }

    setCounterAddress(preview.value.address);
    setStatusMessage(`Active counter address set to ${preview.value.address}.`);
  }

  function handleNormalizeAddress() {
    if (!counterAddress.trim()) {
      return;
    }

    try {
      setCounterAddress(normalizeCounterAddress(counterAddress));
    } catch {
      // Leave the original value in place so the user can fix it.
    }
  }

  const contractExplorerUrl = counterAddress
    ? `${TONVIEWER_URL}/${encodeURIComponent(counterAddress)}`
    : null;

  return (
    <main className="app-shell">
      <section className="hero panel">
        <div className="hero-copy">
          <p className="eyebrow">TON React Template</p>
          <h1>Counter dApp</h1>
          <p className="hero-text">
            Clean AppKit setup, TON Connect wallet flow, deterministic counter
            deployment, and direct contract reads through the generated wrapper.
          </p>
          <div className="network-row">
            <span className="network-pill">{TON_NETWORK_LABEL}</span>
            {walletNetworkMismatch ? (
              <span className="warning-pill">
                Connected wallet uses another network
              </span>
            ) : null}
          </div>
        </div>
        <div className="wallet-panel">
          <TonConnectButton />
          <dl className="wallet-details">
            <div>
              <dt>Wallet</dt>
              <dd>{walletAddress ?? 'Not connected'}</dd>
            </div>
            <div>
              <dt>Balance</dt>
              <dd>
                {walletBalance.data
                  ? `${walletBalance.data} TON`
                  : 'Connect to load'}
              </dd>
            </div>
          </dl>
        </div>
      </section>

      <section className="grid">
        <article className="panel">
          <div className="section-head">
            <div>
              <p className="eyebrow">Step 1</p>
              <h2>Create New Counter</h2>
            </div>
          </div>

          <label className="field">
            <span>Counter ID</span>
            <input
              type="number"
              min="0"
              step="1"
              value={counterId}
              onChange={(event) => setCounterId(event.target.value)}
            />
          </label>

          <label className="field">
            <span>Deploy value (TON)</span>
            <input
              type="text"
              inputMode="decimal"
              value={deployValue}
              onChange={(event) => setDeployValue(event.target.value)}
            />
          </label>

          <div className="preview-card">
            <p className="preview-label">Deterministic deploy address</p>
            <code>{preview.value?.address ?? preview.error}</code>
          </div>

          <div className="button-row">
            <button
              className="primary-button"
              disabled={!walletReady || Boolean(preview.error) || busy}
              onClick={handleDeploy}
              type="button"
            >
              {pendingAction === 'deploy'
                ? 'Creating...'
                : 'Create New Counter'}
            </button>
            <button
              className="ghost-button"
              disabled={!preview.value || busy}
              onClick={handleUsePreviewAddress}
              type="button"
            >
              Use This Address
            </button>
          </div>
        </article>

        <article className="panel">
          <div className="section-head">
            <div>
              <p className="eyebrow">Step 2</p>
              <h2>Work With Counter</h2>
            </div>
            {contractExplorerUrl ? (
              <a
                className="text-link"
                href={contractExplorerUrl}
                rel="noreferrer"
                target="_blank"
              >
                Open in Tonviewer
              </a>
            ) : null}
          </div>

          <label className="field">
            <span>Counter address</span>
            <input
              type="text"
              placeholder="EQ..."
              value={counterAddress}
              onBlur={handleNormalizeAddress}
              onChange={(event) => setCounterAddress(event.target.value)}
            />
          </label>

          <div className="field-grid">
            <label className="field">
              <span>Step</span>
              <input
                type="number"
                min="1"
                step="1"
                value={step}
                onChange={(event) => setStep(event.target.value)}
              />
            </label>
            <label className="field">
              <span>Message value (TON)</span>
              <input
                type="text"
                inputMode="decimal"
                value={messageValue}
                onChange={(event) => setMessageValue(event.target.value)}
              />
            </label>
          </div>

          <div className="counter-readout">
            <p className="preview-label">Current value</p>
            <strong>
              {counterValue.status === 'ready' && counterValue.value !== null
                ? counterValue.value.toString()
                : '—'}
            </strong>
            <p>{counterValue.message}</p>
            {counterValue.fetchedAt ? (
              <span>Updated at {counterValue.fetchedAt}</span>
            ) : null}
          </div>

          <div className="button-row">
            <button
              className="primary-button"
              disabled={!walletReady || busy}
              onClick={() => handleAction('increase')}
              type="button"
            >
              {pendingAction === 'increase' ? 'Increasing...' : 'Increase'}
            </button>
            <button
              className="secondary-button"
              disabled={!walletReady || busy}
              onClick={() => handleAction('decrease')}
              type="button"
            >
              {pendingAction === 'decrease' ? 'Decreasing...' : 'Decrease'}
            </button>
            <button
              className="ghost-button"
              disabled={busy}
              onClick={handleFetch}
              type="button"
            >
              {pendingAction === 'fetch' ? 'Fetching...' : 'Fetch Latest Value'}
            </button>
          </div>
        </article>
      </section>

      <section className="status-strip panel">
        <div>
          <p className="eyebrow">Status</p>
          <p className="status-text">{statusMessage}</p>
        </div>
      </section>
    </main>
  );
}
