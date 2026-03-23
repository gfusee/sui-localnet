import { execSync } from 'child_process';

const LOCALNET_CONTAINER = 'localnet';
const SEAL_CONTAINER = 'seal';
const CONTAINERS = [SEAL_CONTAINER, LOCALNET_CONTAINER];

const LOCALNET_TAG = process.env.LOCALNET_TAG ?? 'local';
const SEAL_TAG = process.env.SEAL_TAG ?? 'local';

const LOCALNET_IMAGE = `ghcr.io/gfusee/sui-localnet/sui-localnet:${LOCALNET_TAG}`;
const SEAL_IMAGE = `ghcr.io/gfusee/sui-localnet/seal-server:${SEAL_TAG}`;

const RPC_URL = 'http://localhost:9000';
const FAUCET_URL = 'http://localhost:9123';

export interface SealConfig {
	seal_package_id: string;
	key_server_object_id: string;
	public_key: string;
	mode?: string;
	seal_server_url?: string;
}

export function cleanup(): void {
	try {
		execSync(`docker rm -f ${CONTAINERS.join(' ')} 2>/dev/null || true`, {
			stdio: 'ignore',
		});
	} catch {
		// Ignore errors during cleanup
	}
}

// Register cleanup on process exit/signals so containers are always removed.
process.on('exit', cleanup);
process.on('SIGINT', () => {
	cleanup();
	process.exit(1);
});
process.on('SIGTERM', () => {
	cleanup();
	process.exit(1);
});

async function sleep(ms: number): Promise<void> {
	return new Promise((r) => setTimeout(r, ms));
}

async function waitFor(
	check: () => boolean,
	label: string,
	timeoutMs = 120_000,
	intervalMs = 2_000,
): Promise<void> {
	const start = Date.now();
	while (Date.now() - start < timeoutMs) {
		if (check()) return;
		await sleep(intervalMs);
	}
	throw new Error(`Timed out waiting for ${label}`);
}

export async function startLocalnet(): Promise<void> {
	cleanup();
	execSync('docker network create sui 2>/dev/null || true', { stdio: 'ignore' });

	execSync(
		[
			'docker run -d',
			`--name ${LOCALNET_CONTAINER}`,
			'--network sui',
			'-p 9000:9000 -p 9123:9123',
			'-e WITH_GRAPHQL=false',
			'-e WITH_INDEXER=false',
			LOCALNET_IMAGE,
		].join(' '),
		{ stdio: 'inherit' },
	);

	// Wait for RPC
	await waitFor(() => {
		try {
			const res = execSync(
				`curl -sf -X POST ${RPC_URL} -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"sui_getObject","params":["0x2",{}]}'`,
				{ stdio: 'pipe', timeout: 5000 },
			).toString();
			return res.includes('"data"');
		} catch {
			return false;
		}
	}, 'localnet RPC');

	// Wait for faucet
	await waitFor(() => {
		try {
			const res = execSync(
				`curl -sf -X POST ${FAUCET_URL}/v2/gas -H "Content-Type: application/json" -d '{"FixedAmountRequest":{"recipient":"0x0000000000000000000000000000000000000000000000000000000000000000"}}'`,
				{ stdio: 'pipe', timeout: 5000 },
			).toString();
			return res.includes('Success');
		} catch {
			return false;
		}
	}, 'localnet faucet');
}

export async function startSeal(
	mode: 'independent' | 'committee',
): Promise<SealConfig> {
	const envFlags = [
		`-e SEAL_MODE=${mode}`,
		'-e SEAL_SERVER_URL=http://localhost:2024',
	];
	if (mode === 'committee') {
		envFlags.push('-e SEAL_COMMITTEE_SIZE=3', '-e SEAL_COMMITTEE_THRESHOLD=2');
	}

	execSync(
		[
			'docker run -d',
			`--name ${SEAL_CONTAINER}`,
			'--network sui',
			'-p 2024:2024',
			...envFlags,
			SEAL_IMAGE,
		].join(' '),
		{ stdio: 'inherit' },
	);

	// Wait for seal.json to be available.
	let config: SealConfig | null = null;
	await waitFor(
		() => {
			try {
				const json = execSync(
					`docker exec ${SEAL_CONTAINER} cat /shared/seal.json 2>/dev/null`,
					{ stdio: 'pipe', timeout: 5000 },
				).toString();
				config = JSON.parse(json);
				return true;
			} catch {
				return false;
			}
		},
		'seal config',
		mode === 'committee' ? 240_000 : 120_000,
	);

	if (!config) throw new Error('Failed to read seal config');

	// Wait for the key server to be reachable on port 2024 (any HTTP response means it's up).
	await waitFor(
		() => {
			try {
				execSync(
					'curl -s -o /dev/null -w "%{http_code}" http://localhost:2024/v1/service 2>/dev/null',
					{ stdio: 'pipe', timeout: 3000 },
				);
				return true;
			} catch {
				return false;
			}
		},
		'key server / aggregator health',
		60_000,
	);

	return config;
}
