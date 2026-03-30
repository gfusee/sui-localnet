import { describe, it, beforeAll, afterAll, expect } from 'vitest';
import {
	cleanup,
	startLocalnet,
	startWalrus,
	readWalrusFile,
} from './docker.js';

const BASE_PORT = 9185;
const COMMITTEE_SIZE = 4; // default in local-testbed.sh

describe('Walrus REST API Base Port', () => {
	beforeAll(async () => {
		await startLocalnet();
		await startWalrus({ restApiBasePort: BASE_PORT });
	});

	afterAll(() => {
		cleanup();
	});

	it('assigns sequential REST API ports to storage nodes', () => {
		for (let i = 0; i < COMMITTEE_SIZE; i++) {
			const config = readWalrusFile(
				`/walrus/working_dir/dryrun-node-${i}.yaml`,
			);
			const expectedPort = BASE_PORT + i;
			// Matches both IPv4 (host:port) and IPv6 ('[::1]:port') formats
			const match = config.match(/^rest_api_address:\s+.+:(\d+)'?$/m);
			expect(match, `node ${i} should have rest_api_address`).not.toBeNull();
			expect(Number(match![1])).toBe(expectedPort);
		}
	});
});
