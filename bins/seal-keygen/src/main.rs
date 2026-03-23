use fastcrypto::groups::bls12381::{G1Element, G2Element, Scalar};
use fastcrypto::groups::GroupElement;
use fastcrypto::serde_helpers::ToFromByteArray;
use fastcrypto_tbls::polynomial::Poly;
use rand::thread_rng;
use serde::Serialize;
use std::num::NonZeroU16;

#[derive(Serialize)]
struct MemberOutput {
    party_id: u16,
    master_share: String,
    partial_pk: String,
}

#[derive(Serialize)]
struct KeygenOutput {
    public_key: String,
    g1_generator: String,
    g2_generator: String,
    members: Vec<MemberOutput>,
}

fn to_hex(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let mut threshold: u16 = 2;
    let mut committee_size: u16 = 3;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--threshold" | "-t" => {
                i += 1;
                threshold = args[i].parse().expect("invalid threshold");
            }
            "--committee-size" | "-n" => {
                i += 1;
                committee_size = args[i].parse().expect("invalid committee size");
            }
            _ => {
                eprintln!("Unknown argument: {}", args[i]);
                std::process::exit(1);
            }
        }
        i += 1;
    }

    assert!(threshold >= 2, "threshold must be >= 2");
    assert!(
        committee_size >= threshold,
        "committee size must be >= threshold"
    );

    let mut rng = thread_rng();

    // Generate random polynomial of degree (threshold - 1) over BLS12-381 scalar field.
    let secret_poly: Poly<Scalar> = Poly::rand(threshold - 1, &mut rng);

    // Commit polynomial to G2 to get public polynomial.
    let public_poly: Poly<G2Element> = secret_poly.commit();

    // Combined public key = constant term of the public polynomial.
    let public_key_bytes = public_poly.c0().to_byte_array();

    // G1 and G2 generators (used as dummy enc_pk and signing_pk for committee registration).
    let g1_gen_bytes = G1Element::generator().to_byte_array();
    let g2_gen_bytes = G2Element::generator().to_byte_array();

    let mut members = Vec::new();

    for party_id in 0..committee_size {
        let share_index = NonZeroU16::new(party_id + 1).expect("party_id + 1 > 0");

        // Evaluate secret polynomial at (party_id + 1) to get this member's share.
        let share = secret_poly.eval(share_index);
        let share_bytes = share.value.to_byte_array();

        // Evaluate public polynomial at (party_id + 1) to get partial public key.
        let partial_pk = public_poly.eval(share_index);
        let partial_pk_bytes = partial_pk.value.to_byte_array();

        members.push(MemberOutput {
            party_id,
            master_share: to_hex(&share_bytes),
            partial_pk: to_hex(&partial_pk_bytes),
        });
    }

    let output = KeygenOutput {
        public_key: to_hex(&public_key_bytes),
        g1_generator: to_hex(&g1_gen_bytes),
        g2_generator: to_hex(&g2_gen_bytes),
        members,
    };

    println!("{}", serde_json::to_string(&output).unwrap());
}
