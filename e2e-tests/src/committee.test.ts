import { describe, it, beforeAll, afterAll } from 'vitest';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { cleanup, startLocalnet, startSeal, type SealConfig } from './docker.js';
import {
	createSuiClient,
	fundAddress,
	deployPolicy,
	createSealClient,
	testEncryptDecrypt,
} from './helpers.js';

describe('Seal Committee Mode', () => {
	let sealConfig: SealConfig;

	beforeAll(async () => {
		await startLocalnet();
		sealConfig = await startSeal('committee');
	});

	afterAll(() => {
		cleanup();
	});

	it('encrypts and decrypts data with a committee of key servers', async () => {
		const suiClient = createSuiClient();
		const keypair = new Ed25519Keypair();

		await fundAddress(keypair.toSuiAddress());
		const policyPkgId = await deployPolicy(suiClient, keypair);

		const sealClient = createSealClient(suiClient, sealConfig, 'committee');

		// Threshold=1 because we talk to 1 aggregator (which internally manages the committee threshold)
		await testEncryptDecrypt(sealClient, suiClient, keypair, policyPkgId, 1);
	});
});
