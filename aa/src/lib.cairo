use starknet::account::Call;

#[starknet::interface]
trait IAccount<T> {
    fn is_valid_signature(self: @T, hash: felt252, signature: Array<felt252>) -> felt252;
    // fn supports_interface(self: @T, interface_id: felt252) -> bool;
}


#[starknet::contract]
mod Account {
    use super::{IAccount, Call};
    use ecdsa::check_ecdsa_signature;
    use starknet::{get_tx_info, get_caller_address, call_contract_syscall};
    use box::BoxTrait;
    use array::{ArrayTrait, SpanTrait};
    
    #[storage]
    struct Storage {
        public_key: felt252
    }

    #[constructor]
    fn constructor(ref self: ContractState, public_key: felt252) {
        self.public_key.write(public_key);
    }

    #[external(v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            let is_valid = self.is_valid_signature_bool(hash, signature.span());

            if is_valid {'VALID'} else {0}
        }
    }

    #[external(v0)]
    #[generate_trait]
    impl ProtocolImpl of ProtocolTrait {
        fn __execute__(calls: Array<Call>) -> Array<Span<felt252>> {
            self.only_protocol();
            self.execute_multiple_calls(calls)
        }

        fn __validate__(calls: Array<Call>) -> felt252 {
            self.only_protocol();
            self.validate_transaction() //no semi-colon at the end bc returning value from this fn
        }

        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            self.only_protocol();
            self.validate_transaction()
        }

        fn __validate_deploy__(self: @ContractState, class_hash: felt252, salt: felt252, public_key: felt252) -> felt252 {
            self.only_protocol();
            self.validate_transaction()
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn is_valid_signature_bool(self: @ContractState, hash: felt252, signature: Span<felt252>) -> bool{
            let is_valid_length = signature.len() == 2_u32;

            if !is_valid_length {
                return false;
            }

            let is_valid = check_ecdsa_signature(
                hash, self.public_key.read(), *signature.at(0_u32), *signature.at(1_u32)
            );

            
        }

        fn only_protocol(self: @ContractState) {
            let sender = get_caller_address();
            //msg cannot be more than 31 chars. 'felt' maxes out at 31 char
            assert(sender.is_zero(), 'Account: Invalid caller');
        }

        fn validate_transaction(self: @ContractState) -> felt252 {
            let tx_info = get_tx_info().unbox();
            let signature = tx_info.signature;
            let tx_hash = tx_info.transaction_hash;

            let is_valid = self.is_valid_signature_bool (tx_hash, signature);
            assert(is_valid, 'Account: Incorrect tx signature');
            'VALID'
        }

        fn execute_multiple_calls (ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            let mut res = ArrayTrait::new();
            loop {
                match calls.pop_front() {
                    Option::Some(call) => {
                        let _res = self.execute_single_call(call);
                        res.append(_res);
                    },
                    Option::None(_) => {
                        break();
                    },
                }
            }

        }

        fn execute_single_call (ref self: ContractState, call: Call) -> Span<felt252> {
            let Call{to, selector, calldata} = call;
            call_contract_syscall(to, selector, calldata.span()).unwrap() //no semicolon bc want to return its value
        }
    }
}


