/*
This module manages the shared assets of the game.
Furies is the cap of the game.
Game is created when the first player joins a game and manages the game with several players
new_empty_game() is called by the front end when the first player enters the game room.
Whenever a game is finished, delete_game() should also be called.
The module also provides functions that return game_rankings records or so when requested. (To do when testing with frontend)
sui move build --silence-warnings
*/
module furies_code::furies_main {
    use std::string::{Self, utf8, String};
    use std::vector;
    use std::debug::print;

    use sui::tx_context::{Self, TxContext};
    use sui::object::{UID, Self};
    use sui::transfer::{Self};
    use sui::random::{Self, Random};
    use sui::vec_map::{Self, VecMap};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    use furies_code::game_randomness::{Self};
    use furies_code::utils::{Self};

    const HOME_ADD:address= 0XHOME;

     // Error codes
    const ECallerNotHouse: u64 = 0;

    //TO DO: 
    //admin_add: address, max_stake: u64, min_stake: u64,
    //TO DO: 
    public struct Furies has key {
        id: UID,
        house: address,
        total_game_player: u64,   //questionable, how to calculate? Implement later
        max_stake: u64,
        min_stake: u64,
        balance_SUI: Balance<SUI>,
        awards_SUI: Balance<SUI>,
        //order list by the SUI amount winned
        game_rankings: vector<Game_record>,
        //order list by the SUI amount winned
        consecutive_win_rankings: vector<Consecutive_win_record>
    }

    //The capbility (When to use??)
    public struct FuriesCap has key {
        id: UID
    }

    //The data for each game
    //Created to be shared in the beginning of each game and destroyed when finished
    public struct Game has key, store{
        id: UID,
        sui_plant: u64,
        sui_marine: u64,
        sui_asmodian: u64,
        total_num_player: u8,
        total_sui_this_game: u64
    }

    //Game ranking record
    public struct Game_record has store, copy, drop {
        winner: String,
        awards: u64,
        time:String
    }

    //Consecutive win ranking record
    public struct Consecutive_win_record has store, copy, drop {
        winner: String,
        awards: u64,
        num_win:u8,
        time:String
    }

    fun init(ctx: &mut TxContext) {
        let furies = Furies {
            id: object::new(ctx),
            house: HOME_ADD,
            total_game_player:0,
            max_stake: 0,
            min_stake: 0,
            balance_SUI: balance::zero(),
            awards_SUI: balance::zero(),
            game_rankings: vector::empty<Game_record>(),
            consecutive_win_rankings: vector::empty<Consecutive_win_record>()
        };

        // Creating and sending the HouseCap object to the sender.
        let furies_cap = FuriesCap {
            id: object::new(ctx)
        };

        transfer::transfer(furies_cap, ctx.sender());
        //random::create(ctx);
        //how to get the Random object???
        transfer::share_object(furies);
    }

    public fun new_game_record(winer_ref:String, awards:u64, time:String): Game_record{
        Game_record{
            winner: winer_ref,
            awards: awards,
            time: time
        }
    }

    public fun new_consecutive_win_record( winer_ref:String, awards:u64, num_win:u8, time:String): Consecutive_win_record{
        Consecutive_win_record{
            winner: winer_ref,
            awards: awards,
            num_win:num_win,
            time:time
        }
    }

    public fun new_empty_game(ctx: &mut TxContext){
        let game = Game {
            id: object::new(ctx),
            sui_plant: 0,
            sui_marine: 0,
            sui_asmodian: 0,
            total_num_player: 0,
            total_sui_this_game: 0,
        };
        transfer::share_object(game);
    }

    public fun delete_game(game: Game){
        let Game {
            id: id1,
            sui_plant: _sui_plant,
            sui_marine: _sui_marine,
            sui_asmodian: _sui_asmodian,
            total_num_player: _total_num_player,
            total_sui_this_game: _total_sui_this_game,
        } = game;
        object::delete(id1);
    }

     /// Returns the max stake of the house.
    public fun max_stake(furies_global: &Furies): u64 {
        furies_global.max_stake
    }

    /// Returns the min stake of the house.
    public fun min_stake(furies_global: &Furies): u64 {
        furies_global.min_stake
    }


    public fun awards_pool(furies_global: &Furies):u64{
        furies_global.awards_SUI.value()
    }

    public fun balance_sui(furies_global: &Furies):u64{
        furies_global.balance_SUI.value()
    }

    public fun withdraw(furies_global: &mut Furies, ctx: &mut TxContext) {
        // Only the house address can withdraw funds.
        assert!(ctx.sender() == furies_global.house, ECallerNotHouse);

        let total_balance = balance_sui(furies_global);
        let coin = coin::take(&mut furies_global.balance_SUI, total_balance, ctx);
        transfer::public_transfer(coin, furies_global.house);
    }

    public fun claim_awards_pool(furies_global: &mut Furies, ctx: &mut TxContext) {
        // Only the house address can withdraw fee funds.
        assert!(ctx.sender() == furies_global.house, ECallerNotHouse);

        let total_fees = awards_pool(furies_global);
        let coin = coin::take(&mut furies_global.awards_SUI, total_fees, ctx);
        transfer::public_transfer(coin, furies_global.house);
    }

    public fun update_max_stake(furies_global: &mut Furies, max_stake: u64, ctx: &mut TxContext) {
        // Only the house address can update the base fee.
        assert!(ctx.sender() == furies_global.house, ECallerNotHouse);
        furies_global.max_stake = max_stake;
    }

    public fun update_min_stake(furies_global: &mut Furies, min_stake: u64, ctx: &mut TxContext) {
        // Only the house address can update the min stake.
        assert!(ctx.sender() == furies_global.house, ECallerNotHouse);
        furies_global.min_stake = min_stake;
    }

    public fun get_total_num_player(game: &Game):u8{
        game.total_num_player
    }

    public fun borrow_game_rankings(furies_global: & Furies): &vector<Game_record>{
        &furies_global.game_rankings

    }

    public fun borrow_consecutive_win_rankings(furies_global: & Furies): &vector<Consecutive_win_record>{
        &furies_global.consecutive_win_rankings
    }

    public(package) fun get_awards_pool_mut(furies_global: &mut Furies):&mut Balance<SUI>{
        &mut furies_global.awards_SUI
    }

    public(package) fun get_balance_sui_mut(furies_global: &mut Furies):&mut Balance<SUI>{
        &mut furies_global.balance_SUI
    }

    public(package) fun get_sui_plant(game: &Game):u64{
        game.sui_plant
    }

    public(package) fun get_sui_marine(game: &Game):u64{
        game.sui_marine
    }

    public(package) fun get_sui_asmodian(game: &Game):u64{
        game.sui_asmodian
    }

    public(package) fun get_total_sui_this_game(game: &Game):u64{
        game.total_sui_this_game
    }

    public(package) fun increase_total_num_player(game: &mut Game){
        game.total_num_player = game.total_num_player + 1
    }

    public(package) fun increase_sui_plant(game: &mut Game, increased_amount:u64){
        game.sui_plant = game.sui_plant + increased_amount
    }

    public(package) fun increase_sui_marine(game: &mut Game, increased_amount:u64){
        game.sui_marine = game.sui_marine + increased_amount
    }

    public(package) fun increase_sui_asmodian(game: &mut Game, increased_amount:u64){
        game.sui_asmodian = game.sui_asmodian + increased_amount
    }

    public(package) fun increase_total_sui_this_game(game: &mut Game, increased_amount:u64){
        game.total_sui_this_game = game.total_sui_this_game + increased_amount
    }

    public(package) fun collect_ticket_payment(furies_global:&mut Furies, ticket: Balance<SUI>){
        furies_global.balance_SUI.join(ticket);
    }

    public(package) fun collect_pool_payment(furies_global:&mut Furies, amount:u64){
        let sui_to_pool = furies_global.balance_SUI.split(amount);
        furies_global.awards_SUI.join(sui_to_pool);
    }


    public(package) fun insert_to_game_rankings(furies_global:&mut Furies, winer_ref:String, awards:u64, time:String){
        let record = new_game_record(winer_ref, awards, time);
        binary_insert_game_record(&mut furies_global.game_rankings,record);
    }

    public(package) fun insert_to_consecutive_win_rankings(furies_global:&mut Furies, winer_ref:String, awards:u64, num_win:u8, time:String){
        let record = new_consecutive_win_record( winer_ref, awards, num_win, time);
        binary_insert_consecutive_win_record(&mut furies_global.consecutive_win_rankings,record);
    }

    fun binary_insert_game_record(list:&mut vector<Game_record>, record:Game_record){
        if(vector::length(list) == 0){
            list.push_back(record);
            return
        };
        let left = 0;
        let right = vector::length(list) - 1;
        let mut found_index = binary_search_game_record(list, &record, left, right);
        if(vector::borrow(list, found_index).awards >= record.awards)
            vector::insert(list, record, found_index)
        else{
            found_index = found_index + 1;
            vector::insert(list, record, found_index);    
        } 
    }

    fun binary_insert_consecutive_win_record(list:&mut vector<Consecutive_win_record>, record:Consecutive_win_record){
        if(vector::length(list) == 0){
            list.push_back(record);
            return
        };
        let left = 0;
        let right = vector::length(list) - 1;
        let mut found_index = binary_search_consecutive_win_record(list, &record, left, right);
        if(vector::borrow(list, found_index).awards >= record.awards)
            vector::insert(list, record, found_index)
        else{
            found_index = found_index + 1;
            vector::insert(list, record, found_index);    
        } 
    }

    fun binary_search_game_record(list:&vector<Game_record>, record:&Game_record, left:u64, right:u64): u64{
        if(left >= right)
            return right
        else{
            let mid = (left + right)/2;
            let cur_val = vector::borrow(list, mid).awards;
            if(cur_val == record.awards)
                return mid
            else if(cur_val > record.awards){
                let new_right;
                if(mid == 0)
                    new_right = mid
                else
                    new_right = mid - 1;
                return binary_search_game_record(list, record, left, new_right)
            }else if(cur_val < record.awards){
                let new_left = mid + 1;
                return binary_search_game_record(list, record, new_left, right) 
            }             
        };        
        right
    }

    fun binary_search_consecutive_win_record(list:&vector<Consecutive_win_record>, record:&Consecutive_win_record, left:u64, right:u64): u64{
        if(left >= right)
            return right
        else{
            let mid = (left + right)/2;
            let cur_val = vector::borrow(list, mid).awards;
            if(cur_val == record.awards)
                return mid
            else if(cur_val > record.awards){
                let new_right;
                if(mid == 0)
                    new_right = mid
                else
                    new_right = mid - 1;
                return binary_search_consecutive_win_record(list, record, left, new_right)
            }else if(cur_val < record.awards){
                let new_left = mid + 1;
                return binary_search_consecutive_win_record(list, record, new_left, right) 
            }             
        };        
        right
    }
    ////////////////////////test   ////////////////////////test    ////////////////////////test
    /// 
    #[test_only]
    public fun print_game_rankings(furies_global: &Furies){
        print_game_record_list(&furies_global.game_rankings)
    }

    #[test_only]
    public fun print_consecutive_win_rankings(furies_global: &Furies){
        print_consecutive_win_record_list(&furies_global.consecutive_win_rankings)
    }

    #[test_only]
    public fun get_new_game_for_test(sui_plant:u64, sui_marine:u64, sui_asmodian:u64, total_num_player:u8, total_sui_this_game:u64, ctx: &mut TxContext): Game {
        Game {
            id: object::new(ctx),
            sui_plant: sui_plant,
            sui_marine: sui_marine,
            sui_asmodian: sui_asmodian,
            total_num_player: total_num_player,
            total_sui_this_game: total_sui_this_game
        }
    }
  
    #[test_only]
    public fun get_furies_global_for_test(ctx: &mut TxContext):Furies{
        Furies {
            id: object::new(ctx),
            total_game_player:0,
            balance_SUI: balance::zero(),
            awards_SUI: balance::zero(),
            game_rankings: vector::empty<Game_record>(),
            consecutive_win_rankings: vector::empty<Consecutive_win_record>()
        }
    }

    #[test_only]
    public fun set_balance_SUI(furies_global: &mut Furies, coin:Coin<SUI>){
        furies_global.balance_SUI.join(coin.into_balance());
    }

    #[test_only]
    public fun set_awards_SUI(furies_global: &mut Furies, coin:Coin<SUI>){
        furies_global.awards_SUI.join(coin.into_balance());
    }
    
    #[test_only]
    public fun delete_furies_global_for_test(furies: Furies){
        let Furies {
            id: id1,
            total_game_player: _total_game_player,
            balance_SUI: balance_SUI,
            awards_SUI: awards_SUI,
            game_rankings: _game_rankings,
            consecutive_win_rankings: _consecutive_win_rankings
        } = furies;
        balance::destroy_for_testing(balance_SUI);
        balance::destroy_for_testing (awards_SUI);
        object::delete(id1);
    }

    //game: id: UID, sui_plant: u64, sui_marine: u64, sui_asmodian: u64, total_num_player: u8, total_sui_this_game: u64
    public fun print_game(g:&Game){
        let mut str: String = utf8(b"Game: ");
        str.append(utf8(b"sui_plant: "));
        str.append(utils::u64_to_string(g.sui_plant));
        str.append(utf8(b", sui_marine: "));
        str.append(utils::u64_to_string(g.sui_marine));
        str.append(utf8(b", sui_asmodian: "));
        str.append(utils::u64_to_string(g.sui_asmodian));
        str.append(utf8(b", number of players: "));
        str.append(utils::u8_to_string(g.total_num_player));
        str.append(utf8(b", total sui: "));
        str.append(utils::u64_to_string(g.total_sui_this_game));
        print(&str);
    }


    
    public fun print_game_record_list(list: &vector<Game_record>){
        let mut i = 0;
        let len = vector::length(list);
        while(i < len){
            let cur = vector::borrow(list, i);
            print_game_record(cur);
            i = i + 1;
        };
    }

    public fun print_consecutive_win_record_list(list: &vector<Consecutive_win_record>){
        let mut i = 0;
        let len = vector::length(list);
        while(i < len){
            let cur = vector::borrow(list, i);
            print_consecutive_win_record(cur);
            i = i + 1;
        };       
    }

    public fun print_game_record(r:&Game_record){
        let mut str: String = utf8(b"Game record: ");
        str.append(r.winner);
        str.append(utf8(b", "));
        str.append(utils::u64_to_string(r.awards));
         str.append(utf8(b", "));
        str.append(r.time);
        print(&str);
    }

    //new_consecutive_win_record( winer_ref:String, awards:u64, num_win:u8, time:String): 
    public fun print_consecutive_win_record(r:&Consecutive_win_record){
        let mut str: String = utf8(b"Consecutive win record: ");
        str.append(r.winner);
        str.append(utf8(b", "));
        str.append(utils::u64_to_string(r.awards));
        str.append(utf8(b", "));
        str.append(utils::u8_to_string(r.num_win));
        str.append(utf8(b", "));
        str.append(r.time);
        print(&str);
    }

    #[test]
    #[allow(unused_assignment)]
    fun test_binary_insert_game_record(){
        let mut list = vector::empty<Game_record>();
        let r1 = new_game_record(utf8(b"player_1"), 1, utf8(b"time_1"));
        let r2 = new_game_record(utf8(b"player_2"), 2, utf8(b"time_2"));
        let r3 = new_game_record(utf8(b"player_3"), 3, utf8(b"time_3"));
        let r4 = new_game_record(utf8(b"player_4"), 4, utf8(b"time_4"));
        let r5 = new_game_record(utf8(b"player_5"), 6, utf8(b"time_5"));
        let r_insert = new_game_record(utf8(b"player_new"), 5, utf8(b"time_new"));
        vector::push_back(&mut list, r1);
        vector::push_back(&mut list, r2);
        vector::push_back(&mut list, r3);
        vector::push_back(&mut list, r4);
        vector::push_back(&mut list, r5);
        binary_insert_game_record(&mut list, r_insert);
        //print_game_record_list(&list);
    }

    #[test]
    #[allow(unused_assignment)]
    fun test_binary_insert_consecutive_win_record(){
        let mut list = vector::empty<Consecutive_win_record>();
        let r1 = new_consecutive_win_record(utf8(b"player_1"), 1, 2, utf8(b"time_1"));
        let r2 = new_consecutive_win_record(utf8(b"player_2"), 2, 3, utf8(b"time_2"));
        let r3 = new_consecutive_win_record(utf8(b"player_3"), 3, 5, utf8(b"time_3"));
        let r4 = new_consecutive_win_record(utf8(b"player_4"), 4, 4, utf8(b"time_4"));
        let r5 = new_consecutive_win_record(utf8(b"player_5"), 5, 3, utf8(b"time_5"));
        let r_insert = new_consecutive_win_record(utf8(b"player_new"), 6, 2, utf8(b"time_new"));
        vector::push_back(&mut list, r1);
        vector::push_back(&mut list, r2);
        vector::push_back(&mut list, r3);
        vector::push_back(&mut list, r4);
        vector::push_back(&mut list, r5);
        binary_insert_consecutive_win_record(&mut list, r_insert);
        //print_consecutive_win_record_list(&list);
    }

}

