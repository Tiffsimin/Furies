module furies_code::utils{
    use std::string::{Self, utf8, String};
    use std::vector;

    use sui::tx_context::{Self, TxContext};
    use sui::object::{UID, Self};
    use sui::transfer::{Self};
    use sui::address::{Self};

    const LEN_REF:u64 = 8;

    public fun covert_add_to_str(add:address):String{
        let list_add = address::to_string(add);
        let str_ref = string::sub_string(&list_add, 0, LEN_REF);
        str_ref
    }

    public fun u8_to_string(mut num: u8): String {
        let mut vec = vector::empty<u8>();
        let mut cur = num % 10;
        vector::insert(&mut vec, cur + 48, 0);
        num = num / 10;
        while(num > 0){
            cur = num % 10;
            vector::insert(&mut vec, cur + 48, 0);
            num = num / 10;
        };
        string::utf8(vec)
    }

    public fun u64_to_string(mut num: u64): String {
        let mut vec = vector::empty<u8>();
        let mut cur = num % 10;
        vector::insert(&mut vec, (cur as u8) + 48, 0);
        num = num / 10;
        while(num > 0){
            cur = num % 10;
            vector::insert(&mut vec, (cur as u8) + 48, 0);
            num = num / 10;
        };
        string::utf8(vec)
    }
}