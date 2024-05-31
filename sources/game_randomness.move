module furies_code::game_randomness{
    use sui::tx_context::{Self, TxContext};
    use sui::object::{UID, Self};
    use sui::transfer::{Self};
    use sui::random::{Self, Random};

    const FIRE:u8= 6;
    const EARTH:u8= 7;
    const WATER:u8= 8;

    public(package) fun get_attack_attribute(r:&Random, ctx:&mut TxContext): u8 {
        let mut generator = random::new_generator(r, ctx); // generator is a PRG
        random::generate_u8_in_range(&mut generator, 5, WATER)
    }


    
}