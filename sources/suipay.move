module suipay::suipay;

use std::string::{String, utf8};
use std::type_name;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::transfer::Receiving;

const ENOT_AUTHORIZED: u64 = 2;
const EWALLET_ALREADY_EXISTS: u64 = 1;

public struct SuiPayTreasury has key, store {
    id: UID,
    wallet: Bag,
    owner: address,
    history: vector<TransactionHistory>,
}

public struct WalletRegistry has key, store {
    id: UID,
    wallets: Table<address, address>, //address of owner, address of autonomouswallet
}

public struct WalletCreationEvent has copy, drop {
    refId: address,
    owner: address,
    wallet_address: address,
}

public struct SUIPAY has drop {}

public struct TransactionHistory has store {
    amount: u64,
    coin: String,
    party: address,
    timestamp: u64,
    memo: String,
    incomming: bool,
}

fun init(_: SUIPAY, ctx: &mut TxContext) {
    let walletsTable = table::new<address, address>(ctx);
    let walletRegistry = WalletRegistry { id: object::new(ctx), wallets: walletsTable };
    transfer::public_share_object(walletRegistry);
}

public fun createSuiPayWallet(
    refId: address,
    walletRegistry: &mut WalletRegistry,
    ctx: &mut TxContext,
) {
    let owner = refId;
    let contains = table::contains(&walletRegistry.wallets, owner);
    if (contains) {
        abort EWALLET_ALREADY_EXISTS
    };
    let wallet = bag::new(ctx);
    let walletUID = object::new(ctx);
    let walletAddress = object::uid_to_address(&walletUID);
    let suiPayTreasury = SuiPayTreasury {
        id: walletUID,
        wallet: wallet,
        owner: owner,
        history: vector::empty<TransactionHistory>(),
    };
    table::add<address, address>(&mut walletRegistry.wallets, owner, walletAddress);
    transfer::public_share_object(suiPayTreasury);
    event::emit(WalletCreationEvent {
        refId: refId,
        owner: owner,
        wallet_address: walletAddress,
    });
}

public fun receive_sui(
    obj: &mut SuiPayTreasury,
    sent: Receiving<Coin<SUI>>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == obj.owner, ENOT_AUTHORIZED);
    let receivedCoin: Coin<SUI> = transfer::public_receive(&mut obj.id, sent);
    depositToSuiPayWallet(receivedCoin, obj, clock, ctx);
}

public fun getSuiPayWalletAddress(treasury: &SuiPayTreasury): address {
    object::uid_to_address(&treasury.id)
}

public fun getSuiPayOwnerAddress(treasury: &SuiPayTreasury): address {
    treasury.owner
}

public fun depositToSuiPayWallet(
    amount: Coin<SUI>,
    suiPayWallet: &mut SuiPayTreasury,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let type_name_struct = type_name::get<SUI>();
    let k = type_name::into_string(type_name_struct).to_string();
    let totalAmount: u64 = coin::value(&amount);
    if (bag::contains<String>(&suiPayWallet.wallet, k)) {
        let original_balance = bag::borrow_mut<String, Balance<SUI>>(&mut suiPayWallet.wallet, k);
        coin::put<SUI>(original_balance, amount);
    } else {
        bag::add(&mut suiPayWallet.wallet, k, balance::zero<SUI>());
        let original_balance = bag::borrow_mut<String, Balance<SUI>>(&mut suiPayWallet.wallet, k);
        coin::put<SUI>(original_balance, amount);
    };
    let transactionHistory = TransactionHistory {
        amount: totalAmount,
        coin: k,
        party: ctx.sender(),
        timestamp: clock.timestamp_ms(),
        memo: utf8(b"Deposited Externally"),
        incomming: true,
    };
    vector::push_back(&mut suiPayWallet.history, transactionHistory);
}

public(package) fun depositToSuiPayWalletWithCustomTransaction(
    amount: Coin<SUI>,
    suiPayWallet: &mut SuiPayTreasury,
    transactionHistory: TransactionHistory,
) {
    let type_name_struct = type_name::get<SUI>();
    let k = type_name::into_string(type_name_struct).to_string();
    if (bag::contains<String>(&suiPayWallet.wallet, k)) {
        let original_balance = bag::borrow_mut<String, Balance<SUI>>(&mut suiPayWallet.wallet, k);
        coin::put<SUI>(original_balance, amount);
    } else {
        bag::add(&mut suiPayWallet.wallet, k, balance::zero<SUI>());
        let original_balance = bag::borrow_mut<String, Balance<SUI>>(&mut suiPayWallet.wallet, k);
        coin::put<SUI>(original_balance, amount);
    };
    vector::push_back(&mut suiPayWallet.history, transactionHistory);
}

public fun withdrawToAddressFromSuiPayWallet(
    amount: u64,
    suiPayWallet: &mut SuiPayTreasury,
    withdrawl_address: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == suiPayWallet.owner, ENOT_AUTHORIZED);
    let type_name_struct = type_name::get<SUI>();
    let k = type_name::into_string(type_name_struct).to_string();
    let my_balance = bag::borrow_mut<String, Balance<SUI>>(&mut suiPayWallet.wallet, k);
    let needed_coin = coin::take<SUI>(my_balance, amount, ctx);
    transfer::public_transfer(needed_coin, withdrawl_address);
    let transactionHistory = TransactionHistory {
        amount: amount,
        coin: k,
        party: ctx.sender(),
        timestamp: clock.timestamp_ms(),
        memo: utf8(b"Withdrawn to Address"),
        incomming: false,
    };
    vector::push_back(&mut suiPayWallet.history, transactionHistory);
}

public(package) fun transferFromOneTreasuryToAnother(
    amount: u64,
    productName: String,
    fromWallet: &mut SuiPayTreasury,
    toWallet: &mut SuiPayTreasury,
    clock: &Clock,
    ref_id: String,
    ctx: &mut TxContext,
) {
    let type_name_struct = type_name::get<SUI>();
    let k = type_name::into_string(type_name_struct).to_string();
    let my_balance = bag::borrow_mut<String, Balance<SUI>>(&mut fromWallet.wallet, k);
    let needed_coin = coin::take<SUI>(my_balance, amount, ctx);
    let mut str1 = b"Payment by #".to_string();
    str1.append(ref_id);

    let transactionHistory = TransactionHistory {
        amount: amount,
        coin: k,
        party: ctx.sender(),
        timestamp: clock.timestamp_ms(),
        memo: str1,
        incomming: true,
    };
    let mut str2 = b"Payment to #".to_string();
    str2.append(productName);

    let outgoingTransactionHistory = TransactionHistory {
        amount: amount,
        coin: k,
        party: ctx.sender(),
        timestamp: clock.timestamp_ms(),
        memo: str2,
        incomming: false,
    };
    vector::push_back(&mut fromWallet.history, outgoingTransactionHistory);
    depositToSuiPayWalletWithCustomTransaction(
        needed_coin,
        toWallet,
        transactionHistory,
    );
}
