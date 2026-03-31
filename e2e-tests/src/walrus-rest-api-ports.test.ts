import { describe, it, beforeAll, afterAll, expect } from 'vitest';
import { execSync } from 'child_process';
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

	it(
		'storage nodes are reachable on their assigned ports',
		async () => {
			for (let i = 0; i < COMMITTEE_SIZE; i++) {
				const port = BASE_PORT + i;
				let lastError: unknown;

				// Nodes may still be starting up after log file appears — retry for up to 30s.
				// Curl from inside the container since nodes may listen on [::1] (IPv6 loopback).
				const deadline = Date.now() + 30_000;
				while (Date.now() < deadline) {
					try {
						const res = execSync(
							`docker exec walrus curl -sfk -o /dev/null -w "%{http_code}" "https://[::1]:${port}/v1/health"`,
							{ stdio: 'pipe', timeout: 5000 },
						).toString();
						const code = Number(res);
						expect(
							code,
							`node ${i} at port ${port} should return 2xx`,
						).toBeGreaterThanOrEqual(200);
						expect(code).toBeLessThan(300);
						lastError = null;
						break;
					} catch (e) {
						lastError = e;
						await new Promise((r) => setTimeout(r, 2000));
					}
				}
				if (lastError) {
					throw new Error(
						`node ${i} at port ${port} is not reachable — on-chain address may not match listen port`,
					);
				}
			}
		},
		60_000,
	);
});
