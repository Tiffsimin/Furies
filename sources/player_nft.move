/*
Most of the interactions with the frontend and player throughout the game are handled here.
There are 4 points of time when frontend needs to call functions here.
1. When a player enter the game and want to play the first time, the nft is mint and sent to the player, mint_to_sender is called.
2. After the player selects the land/race, start_new_game is called
3. When the player decides how much ticket to pay and pay the price, player_pay_ticket s called
4. When there are enough players, the game starts, attack_and_process_result is called
Other than that, when some records are required, the functions can be called to extract the records.
*/
module furies_code::player_nft{
    use std::string::{Self, utf8, String};
    use std::vector;
    use std::debug::print;

    use sui::tx_context::{Self, TxContext};
    use sui::object::{UID, Self};
    use sui::transfer::{Self};
    use sui::url::{Self, Url};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::random::{Self, Random};

    use furies_code::furies_main::{Self, Game, Furies};
    use furies_code::game_randomness::{Self};
    use furies_code::utils::{Self};

    const WIN:u8= 0;
    const LOSE:u8= 1;
    const TIE:u8= 2;
    const UNKNOWN:u8= 3;
    const PLANT:u8= 3;
    const ASMODIANS:u8= 4;
    const MARINE:u8= 5;
    const FIRE:u8= 6;
    const EARTH:u8= 7;
    const WATER:u8= 8;
    const FOUR_WIN:u8= 4;
    const SIX_WIN:u8= 6;
    const TEN_WIN:u8= 10;
    const FOUR_WIN_PERCENTAGE:u64= 8;
    const SIX_WIN_PERCENTAGE:u64= 25;
    const TEN_WIN_PERCENTAGE:u64= 50;
    const FEE_PERCENTAGE:u64= 5;
    const NUM_PLAYERS_SET:u8= 5;

    const ERR_WRONG_NUM_PLAYERS:u64 = 100;
    const ERR_NOT_ENOUGH:u64 = 101;
    const EStakeTooLow: u64 = 102;
    const EStakeTooHigh: u64 = 103;

    public struct Player_NFT has key, store {
        id: UID,
        name: String,
        race:u8,
        last_result:u8,
        this_result:u8,
        ticket_paid:u64,       
        sui_winned_this_game:u64,
        sui_consecutive_win: u64,
        sui_winned_total:u64,
        num_consecutive_win: u8,
        description: String,
        game_history:vector<Record>,
        create_time:String,
        url: Url
    }

    public struct Record has store, copy, drop {
        name: String,
        race:u8,
        boss_attack:u8,
        ticket_paid:u64,
        awards:u64,
        time:String,
    }

    //Player ctx
    #[lint_allow(self_transfer)]
    public fun mint_to_sender(description: String, url: vector<u8>, create_time:String, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let name = utils::covert_add_to_str(sender);
        let nft = Player_NFT {
            id: object::new(ctx),
            name: name,
            race:0,
            last_result:0,
            this_result:0,
            ticket_paid:0,       
            sui_winned_this_game:0,
            sui_consecutive_win: 0,
            sui_winned_total:0,
            num_consecutive_win: 0,
            description: description,
            game_history:vector::empty<Record>(),
            create_time:create_time,
            url: url::new_unsafe_from_bytes(url)
        };
        transfer::public_transfer(nft, sender);
    }

    public fun burn_player_nft(nft: Player_NFT){
        let Player_NFT {
            id,
            name: _,
            race:_,
            last_result:_,
            this_result:_,
            ticket_paid:_,       
            sui_winned_this_game:_,
            sui_consecutive_win: _,
            sui_winned_total:_,
            num_consecutive_win: _,
            description: _,
            game_history:_,
            create_time:_,
            url: _
        } = nft;
        object::delete(id)
    }


    public fun new_record(name:String, race:u8, boss_attack:u8, ticket_paid:u64, awards:u64, time:String):Record{
        //time stamp is created here
        Record{
            name: name,
            race:race,
            boss_attack:boss_attack,
            ticket_paid: ticket_paid,
            awards:awards,
            time:time,
        }
    }

    //called when player select a race, the race is from the front
    //race: plant, asmodians, marine
    public fun start_new_game(nft:&mut Player_NFT, game:&mut Game, race:String){
        nft.last_result = nft.this_result;
        nft.this_result = UNKNOWN;
        if(race == utf8(b"plant"))
            nft.race = PLANT
        else if (race == utf8(b"asmodians"))
            nft.race = ASMODIANS
        else if (race == utf8(b"marine"))
            nft.race = MARINE;
        furies_main::increase_total_num_player(game);       
    }

    //pay sui to play, it is called after start_new_game called so the race is chosen
    //The function assumes that the coin smashing is done by PTB called on the frontend, if not done, the 
    //payment input could be coins:vector<Coin<SUI>> and do the coin smashing in the code (check chess::mint_arena_chess)
    public fun player_pay_ticket(nft:&mut Player_NFT, game:&mut Game, furies_global:&mut Furies, payment:&mut Coin<SUI>, ticket_price:u64){
        assert!(ticket_price >= furies_global.min_stake., EStakeTooLow);
        assert!(ticket_price <= furies_global.max_stake, EStakeTooHigh);
        assert!(coin::value(payment) >= ticket_price, ERR_NOT_ENOUGH);
        let coin_balance = coin::balance_mut(payment);
        let paid = balance::split(coin_balance, ticket_price);
        furies_main::collect_ticket_payment(furies_global, paid);
        nft.ticket_paid = ticket_price;
        
        if(nft.race == PLANT)
            furies_main::increase_sui_plant(game, ticket_price)
        else if(nft.race == ASMODIANS)
            furies_main::increase_sui_asmodian(game, ticket_price)
        else if(nft.race == MARINE)
            furies_main::increase_sui_marine(game, ticket_price);
        furies_main::increase_total_sui_this_game(game, ticket_price);
    }


    //called when frontend is sure that there are enough players, output is the awards of the game, the awards of consecutive win
    //and the number of consecutive wins
    //the time string is taken from frontend
    //Player ctx
    entry fun attack_and_process_result(furies_global:&mut Furies, nft:&mut Player_NFT, game:&Game, time:String, r:&Random, ctx: &mut TxContext):(u64, u64, u8){
        assert!(game.get_total_num_player() == NUM_PLAYERS_SET, ERR_WRONG_NUM_PLAYERS);

        let attack_attribute = game_randomness::get_attack_attribute(r,ctx);

        if(attack_attribute == FIRE){
            //test///
            print(&utf8(b"Result: fire "));
            //test///
            if(nft.race == PLANT)
                nft.this_result = LOSE
            else if(nft.race == ASMODIANS)
                nft.this_result = TIE
            else {                  //race == MARINE
                nft.this_result = WIN;
            };
        }else if(attack_attribute == EARTH){
            //test///
            print(&utf8(b"Result: earth "));
            //test///
            if(nft.race == PLANT)
                nft.this_result = TIE
            else if(nft.race == ASMODIANS){
                nft.this_result = WIN;
            }else                   //race == MARINE
                nft.this_result = LOSE;

        }else{
            //test///
            print(&utf8(b"Result: water "));
            //test///
            //attack_attribute == WATER
            if(nft.race == PLANT){
                nft.this_result = WIN;
            }else if(nft.race == ASMODIANS)
                nft.this_result = LOSE
            else                   //race == MARINE
                nft.this_result = TIE;
        };
        if(nft.this_result == WIN){
            nft.num_consecutive_win = nft.num_consecutive_win + 1;
            calculate_and_send_consecutive_awards(nft, furies_global, time, ctx);
        }else
            nft.num_consecutive_win = 0;
        calculate_and_send_game_awards(furies_global, nft, game, ctx);
        let record = new_record(nft.name, nft.race, attack_attribute, nft.ticket_paid, nft.sui_winned_this_game, time);
        vector::push_back(&mut nft.game_history, record);
        let num_consecutive_win = nft.num_consecutive_win;
        if(nft.this_result == WIN)
            furies_main::insert_to_game_rankings(furies_global, nft.name, nft.sui_winned_this_game, time);
        if(num_consecutive_win == 10)
            nft.num_consecutive_win = 0;
        (nft.sui_winned_this_game, nft.sui_consecutive_win, num_consecutive_win)
    }

    fun set_consecutive_win(nft:&mut Player_NFT){
        if(nft.last_result == WIN)
            nft.num_consecutive_win = nft.num_consecutive_win + 1
        else 
            nft.num_consecutive_win = 0;
    }

    #[lint_allow(self_transfer)]
    fun calculate_and_send_consecutive_awards(nft:&mut Player_NFT, furies_global:&mut Furies, time:String, ctx: &mut TxContext){
        let pool_amount = furies_global.get_awards_pool_amount();
        let mut awards_amount = 0;
        if(nft.num_consecutive_win == FOUR_WIN){
            awards_amount = pool_amount*FOUR_WIN_PERCENTAGE/100;
            furies_main::insert_to_consecutive_win_rankings(furies_global, nft.name, awards_amount, FOUR_WIN, time);
        }else if(nft.num_consecutive_win == SIX_WIN){
            awards_amount = pool_amount*SIX_WIN_PERCENTAGE/100;
            furies_main::insert_to_consecutive_win_rankings(furies_global, nft.name, awards_amount, SIX_WIN, time);
        }else if(nft.num_consecutive_win == TEN_WIN){
            awards_amount = pool_amount*TEN_WIN_PERCENTAGE/100;
            furies_main::insert_to_consecutive_win_rankings(furies_global, nft.name, awards_amount, TEN_WIN, time);
        };
        nft.sui_consecutive_win = awards_amount;
        nft.sui_winned_total =  nft.sui_winned_total + awards_amount;
        //paymend handling
        //should be commented out when testing
        send_consecutive_win_awards_to_player(furies_global, awards_amount, ctx);
    }

    #[lint_allow(self_transfer)]
    fun calculate_and_send_game_awards(furies_global:&mut Furies, nft:&mut Player_NFT, game:&Game, ctx: &mut TxContext){
        //default, could change
        let mut sui_base = game.get_sui_asmodian();
        let mut awards = 0;
        let result = nft.this_result;
        if(result == LOSE){
            nft.sui_winned_this_game = awards;
            //no sui return to player
            return 
        }else if(result == TIE){
            nft.sui_winned_this_game = awards;
            //ticket price returned to player
            //paymend handling
            //should be commented out when testing
            send_sui_to_player(furies_global, nft.ticket_paid, ctx);
            return 
        };
        let winning_race = nft.race;
        if(winning_race == PLANT)
            sui_base = game.get_sui_plant()
        else if(winning_race == MARINE)
            sui_base = game.get_sui_marine();

        let total = nft.ticket_paid * game.get_total_sui_this_game()/sui_base;
        awards = total*(100-FEE_PERCENTAGE)/100;
        let fee_amount = total*FEE_PERCENTAGE/100;
        nft.sui_winned_this_game = awards;
        nft.sui_winned_total =  nft.sui_winned_total + awards;
        /*     
        */
        //paymend handling
        //can be commented out when testing
        send_sui_to_player(furies_global, awards, ctx);
        furies_main::collect_pool_payment(furies_global, fee_amount);
        //paymend handling  

    }

    #[lint_allow(self_transfer)]
    fun send_sui_to_player(furies_global:&mut Furies, amount:u64, ctx: &mut TxContext){
        let player_add = tx_context::sender(ctx);
        let to_pay = coin::take(furies_global.get_balance_sui_mut(), amount, ctx);

        transfer::public_transfer(to_pay, player_add);
    }
    #[lint_allow(self_transfer)]
    fun send_consecutive_win_awards_to_player(furies_global:&mut Furies, amount:u64, ctx: &mut TxContext){
        let player_add = tx_context::sender(ctx);
        let to_pay = coin::take(furies_global.get_awards_pool_mut(), amount, ctx);
        transfer::public_transfer(to_pay, player_add);
    }

    //////////////////Test from here /////////////////////////////////////////////////
    
    /// Record: name: String, race:u8, boss_attack:u8, ticket_paid:u64, awards:u64, time:String,
    public fun print_record(r:&Record){
        let mut str: String = utf8(b"Record: ");
        str.append(utf8(b"Name: "));
        str.append(r.name);
        str.append(utf8(b", race: "));
        str.append(utils::u8_to_string(r.race));
        str.append(utf8(b", boss_attack: "));
        str.append(utils::u8_to_string(r.boss_attack));
        str.append(utf8(b", ticket paid: "));
        str.append(utils::u64_to_string(r.ticket_paid));
        str.append(utf8(b", total awards: "));
        str.append(utils::u64_to_string(r.awards));
        str.append(utf8(b", time: "));
        str.append(r.time);
        print(&str);
    }

    #[test]
    fun test_start_and_pay(){ 
        let mut ctx = tx_context::dummy();

        let time: String =  utf8(b"My time");
        let mut furies_global = furies_main::get_furies_global_for_test(&mut ctx);
        let coin_1 = coin::mint_for_testing<SUI>(5_000, &mut ctx);
        let coin_2 = coin::mint_for_testing<SUI>(1_000, &mut ctx);
        furies_global.set_balance_SUI(coin_1);
        furies_global.set_awards_SUI(coin_2);

        let mut nft = Player_NFT {
            id: object::new(&mut ctx),
            name: utf8(b"Tiff"),
            race:PLANT,   //PLANT:1235, MARINE:926, ASMODIANS:617, 
            last_result:WIN,    //WIN, LOSE, TIE, UNKNOWN: 0,1,2,3
            this_result:UNKNOWN,
            ticket_paid: 200,       
            sui_winned_this_game:0,
            sui_consecutive_win: 0,
            sui_winned_total:0,
            num_consecutive_win: 2,
            description: utf8(b"A testing cutie"),
            game_history:vector::empty<Record>(),
            create_time:utf8(b"One point in time"),
            url: url::new_unsafe_from_bytes(vector::empty<u8>())
        };
        //sui_plant, sui_marine, sui_asmodian, total_num_player, total_sui_this_game
        let mut game = furies_main::get_new_game_for_test(600, 500, 1_200, 5, 2_300, &mut ctx);

        ////race: plant, asmodians, marine
        let race =  utf8(b"marine");   
        
        let mut payment = coin::mint_for_testing<SUI>(1000, &mut ctx);
        let ticket_price = 500;

        //nft:&mut Player_NFT, game:&mut Game, race:String
        start_new_game(&mut nft, &mut game, race);

        //nft:&mut Player_NFT, game:&mut Game, furies_global:&mut Furies,payment:&mut Coin<SUI>, ticket_price:u64
        player_pay_ticket(&mut nft, &mut game, &mut furies_global, &mut payment, ticket_price);

        print(&payment.value());
        print(&nft.last_result);
        print(&nft.this_result);
        print(&nft.ticket_paid);

        furies_main::print_game(&game);

        coin::burn_for_testing(payment);
        furies_main::delete_game(game);
        furies_main::delete_furies_global_for_test(furies_global);
        burn_player_nft(nft);
    }

    #[test]
    fun test_attack_and_process_result(){
        use sui::test_scenario::{Self};

        let mut ctx = tx_context::dummy();
        let mut ts = test_scenario::begin(@0x0);
        let time: String =  utf8(b"My time");
        let mut furies_global = furies_main::get_furies_global_for_test(&mut ctx);

        let coin_1 = coin::mint_for_testing<SUI>(5_000, &mut ctx);
        let coin_2 = coin::mint_for_testing<SUI>(1_000, &mut ctx);
        furies_global.set_balance_SUI(coin_1);
        furies_global.set_awards_SUI(coin_2);

        let mut nft = Player_NFT {
            id: object::new(&mut ctx),
            name: utf8(b"Tiff"),
            race:ASMODIANS,   //PLANT:1235, MARINE:926, ASMODIANS:617, 
            last_result:WIN,    //WIN, LOSE, TIE, UNKNOWN: 0,1,2,3
            this_result:UNKNOWN,
            ticket_paid: 300,       
            sui_winned_this_game:0,
            sui_consecutive_win: 0,
            sui_winned_total:0,
            num_consecutive_win: 3,
            description: utf8(b"A testing cutie"),
            game_history:vector::empty<Record>(),
            create_time:utf8(b"One point in time"),
            url: url::new_unsafe_from_bytes(vector::empty<u8>())
        };
        //
        let mut game = furies_main::get_new_game_for_test(600, 800, 1_200, 5, 2_600, &mut ctx);
        // Setup randomness
        random::create_for_testing(ts.ctx());
        ts.next_tx(@0x0);
        let r: Random = ts.take_shared();

        let mut i = 0;
        while(i < 3){
        //(furies_global:&mut Furies, nft:&mut Player_NFT, game:&Game, time:String, r:&Random, ctx: &mut TxContext):(u64, u64, u8)
            let (sui_winned_this_game, sui_consecutive_win, num_consecutive_win) = 
                attack_and_process_result(&mut furies_global, &mut nft, &game, time, &r, &mut ctx);
            
            //WIN, LOSE, TIE, UNKNOWN: 0,1,2,3
            print(&nft.this_result);
            print(&sui_winned_this_game);
            print(&sui_consecutive_win);
            print(&nft.sui_winned_total);
            print(&num_consecutive_win);

            print(&utf8(b"Game total Sui amount: "));
            print(&furies_global.get_balance_sui_amount());
            print(&utf8(b"Awards pool Sui amount: "));
            print(&furies_global.get_awards_pool_amount());

            i = i + 1;
        };

        furies_global.print_game_rankings();
        furies_global.print_consecutive_win_rankings();

        test_scenario::return_shared(r);
        ts.end();
        furies_main::delete_game(game);
        furies_main::delete_furies_global_for_test(furies_global);
        burn_player_nft(nft);
    }

    #[test]
    #[allow(unused_assignment)]
    fun test_calculate_and_send_consecutive_awards(){
        let mut ctx = tx_context::dummy();
        let time: String =  utf8(b"My time");
        let mut furies_global = furies_main::get_furies_global_for_test(&mut ctx);

        let coin_1 = coin::mint_for_testing<SUI>(5_000_000_000, &mut ctx);
        let coin_2 = coin::mint_for_testing<SUI>(1_000_000_000, &mut ctx);
        furies_global.set_balance_SUI(coin_1);
        furies_global.set_awards_SUI(coin_2);

        let mut nft = Player_NFT {
            id: object::new(&mut ctx),
            name: utf8(b"Tiff"),
            race:0,
            last_result:0,
            this_result:0,
            ticket_paid:0,       
            sui_winned_this_game:0,
            sui_consecutive_win: 0,
            sui_winned_total:0,
            num_consecutive_win: 10,
            description: utf8(b"A testing cutie"),
            game_history:vector::empty<Record>(),
            create_time:utf8(b"One point in time"),
            url: url::new_unsafe_from_bytes(vector::empty<u8>())
        };
        //nft:&mut Player_NFT, furies_global:&mut Furies, time:String, ctx: &mut TxContext
        calculate_and_send_consecutive_awards(&mut nft, &mut furies_global, time, &mut ctx );

        //4 win: 8%; 6 win: 25% 10 win:50%
        print(&nft.sui_consecutive_win);
        print(&nft.sui_winned_total);

        furies_main::delete_furies_global_for_test(furies_global);
        burn_player_nft(nft);
    }

    #[test]
    #[allow(unused_assignment)]
    fun test_calculate_and_send_game_awards(){
        let mut ctx = tx_context::dummy();
        let mut furies_global = furies_main::get_furies_global_for_test(&mut ctx);
        //important
        let coin_1 = coin::mint_for_testing<SUI>(5_000_000_000, &mut ctx);
        let coin_2 = coin::mint_for_testing<SUI>(7_000_000_000, &mut ctx);
        furies_global.set_balance_SUI(coin_1);
        furies_global.set_awards_SUI(coin_2);

        let mut nft = Player_NFT {
            id: object::new(&mut ctx),
            name: utf8(b"Tiff"),
            race:ASMODIANS,   //PLANT:1235, MARINE:926, ASMODIANS:617, 
            last_result:WIN,    //WIN, LOSE, TIE
            this_result:TIE,
            ticket_paid: 300,       
            sui_winned_this_game:0,
            sui_consecutive_win: 0,
            sui_winned_total:0,
            num_consecutive_win: 0,
            description: utf8(b"A testing cutie"),
            game_history:vector::empty<Record>(),
            create_time:utf8(b"One point in time"),
            url: url::new_unsafe_from_bytes(vector::empty<u8>())
        };
        //sui_plant, sui_marine, sui_asmodian, total_num_player, total_sui_this_game
        let mut game = furies_main::get_new_game_for_test(600, 800, 1200, 5, 2600, &mut ctx);
        //furies_global:&mut Furies, nft:&mut Player_NFT, game:&Game, ctx: &mut TxContext
        calculate_and_send_game_awards(&mut furies_global, &mut nft, &game, &mut ctx);

        print(&nft.sui_winned_this_game);
        print(&nft.sui_winned_total);

        furies_main::delete_furies_global_for_test(furies_global);
        furies_main::delete_game(game);
        burn_player_nft(nft);
    }
    
        
}