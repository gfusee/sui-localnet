import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { SealClient, SessionKey } from '@mysten/seal';
import { fromHex, toHex } from '@mysten/bcs';
import { expect } from 'vitest';
import { POLICY_MODULES, POLICY_DEPENDENCIES } from './policy-bytecode.js';
import type { SealConfig } from './docker.js';

const RPC_URL = 'http://localhost:9000';
const FAUCET_URL = 'http://localhost:9123';

export function createSuiClient(): SuiGrpcClient {
	return new SuiGrpcClient({ network: 'custom', baseUrl: RPC_URL });
}

export async function fundAddress(address: string): Promise<void> {
	const res = await fetch(`${FAUCET_URL}/v2/gas`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ FixedAmountRequest: { recipient: address } }),
	});
	if (!res.ok) throw new Error(`Faucet failed: ${res.statusText}`);
	const data = (await res.json()) as { status: string };
	if (data.status !== 'Success')
		throw new Error(`Faucet error: ${JSON.stringify(data)}`);
}

export async function deployPolicy(
	client: SuiGrpcClient,
	keypair: Ed25519Keypair,
): Promise<string> {
	const tx = new Transaction();
	const [upgradeCap] = tx.publish({
		modules: POLICY_MODULES,
		dependencies: POLICY_DEPENDENCIES,
	});
	tx.transferObjects([upgradeCap], keypair.toSuiAddress());

	const result = await client.signAndExecuteTransaction({
		transaction: tx,
		signer: keypair,
		include: { effects: true },
	});

	if (result.$kind !== 'Transaction') {
		throw new Error(`Transaction failed: ${JSON.stringify(result)}`);
	}

	const effects = result.Transaction.effects!;
	const published = effects.changedObjects.find(
		(o) => o.outputState === 'PackageWrite' && o.idOperation === 'Created',
	);
	if (!published) {
		throw new Error('Failed to find published package in transaction effects');
	}

	// Wait for the transaction to be fully indexed before returning.
	await client.waitForTransaction({ digest: effects.transactionDigest });

	// Additional wait to ensure the package is visible to all RPC clients (including the key server's).
	// The key server uses JSON-RPC while the test uses gRPC — they may have different indexing latencies.
	await new Promise((r) => setTimeout(r, 15000));

	return published.objectId;
}

export function createSealClient(
	suiClient: SuiGrpcClient,
	config: SealConfig,
	mode: 'independent' | 'committee',
): SealClient {
	const serverConfig: {
		objectId: string;
		weight: number;
		aggregatorUrl?: string;
	} = {
		objectId: config.key_server_object_id,
		weight: 1,
	};

	if (mode === 'committee') {
		serverConfig.aggregatorUrl = 'http://localhost:2024';
	}

	return new SealClient({
		suiClient,
		serverConfigs: [serverConfig],
		verifyKeyServers: false,
	});
}

export async function testEncryptDecrypt(
	sealClient: SealClient,
	suiClient: SuiGrpcClient,
	keypair: Ed25519Keypair,
	policyPkgId: string,
	threshold: number,
): Promise<void> {
	const plaintext = new TextEncoder().encode('Hello, Seal E2E!');
	const idBytes = crypto.getRandomValues(new Uint8Array(32));
	const id = toHex(idBytes);

	// Encrypt
	const { encryptedObject } = await sealClient.encrypt({
		threshold,
		packageId: policyPkgId,
		id,
		data: plaintext,
	});

	expect(encryptedObject).toBeDefined();
	expect(encryptedObject.length).toBeGreaterThan(0);

	// Create session key for decryption
	const sessionKey = await SessionKey.create({
		address: keypair.toSuiAddress(),
		packageId: policyPkgId,
		ttlMin: 10,
		signer: keypair,
		suiClient,
	});

	// Build seal_approve transaction
	const tx = new Transaction();
	tx.moveCall({
		target: `${policyPkgId}::test_policy::seal_approve`,
		arguments: [tx.pure.vector('u8', Array.from(fromHex(id)))],
	});
	const txBytes = await tx.build({
		client: suiClient,
		onlyTransactionKind: true,
	});

	// Decrypt
	const decrypted = await sealClient.decrypt({
		data: encryptedObject,
		sessionKey,
		txBytes,
	});

	expect(new Uint8Array(decrypted)).toEqual(plaintext);
}
