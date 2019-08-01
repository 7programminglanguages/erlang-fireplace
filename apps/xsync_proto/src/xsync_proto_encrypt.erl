%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_proto_encrypt.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  5 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_proto_encrypt).

-export([
         get_rsa_private_keys/0,
         get_rsa_public_keys/0,
         encrypt_private/2,
         decrypt_private/2,
         encrypt_public/2,
         decrypt_public/2,
         encrypt/3,
         decrypt/3
]).

%%%===================================================================
%%% API
%%%===================================================================

encrypt_private(PlainText, none) ->
    PlainText;
encrypt_private(PlainText, PrivateKey) ->
    public_key:encrypt_private(PlainText, PrivateKey).

decrypt_private(CipherText, none) ->
    CipherText;
decrypt_private(CipherText, PrivateKey) ->
    try public_key:decrypt_private(CipherText, PrivateKey) of
        PlainText ->
            PlainText
    catch
        _:_ ->
            error
    end.

encrypt_public(PlainText, none) ->
    PlainText;
encrypt_public(PlainText, PrivateKey) ->
    public_key:encrypt_public(PlainText, PrivateKey).

decrypt_public(CipherText, none) ->
    CipherText;
decrypt_public(CipherText, PrivateKey) ->
    try public_key:decrypt_public(CipherText, PrivateKey) of
        PlainText ->
            PlainText
    catch
        _:_ ->
            error
    end.

encrypt(PlainText, 'ENCRYPT_NONE', _EncryptKey) ->
    PlainText;
encrypt(PlainText, 'AES_CBC_128', EncryptKey) ->
    crypto:block_encrypt(aes_cbc128, EncryptKey, get_symm_ivec(), padding(PlainText));
encrypt(PlainText, 'AES_CBC_256', EncryptKey) ->
    crypto:block_encrypt(aes_cbc256, EncryptKey, get_symm_ivec(), padding(PlainText)).


decrypt(CipherText, 'ENCRYPT_NONE', _EncryptKey) ->
    CipherText;
decrypt(CipherText, 'AES_CBC_128', EncryptKey) ->
    try crypto:block_decrypt(aes_cbc128, EncryptKey, get_symm_ivec(), CipherText) of
        error ->
            error;
        PlainText ->
            remove_padding(PlainText)
    catch
        _:_ ->
            error
    end;
decrypt(CipherText, 'AES_CBC_256', EncryptKey) ->
    try crypto:block_decrypt(aes_cbc256, EncryptKey, get_symm_ivec(), CipherText) of
        error ->
            error;
        PlainText ->
            remove_padding(PlainText)
    catch
        _:_ ->
            error
    end.

get_rsa_private_keys() ->
    Keys = application:get_env(xsync_proto, private_keys, [none]),
    lists:map(
      fun(none) ->
              none;
         (KeyBin) ->
            [DSAEntry] = public_key:pem_decode(KeyBin),
            public_key:pem_entry_decode(DSAEntry)
      end, Keys).

get_rsa_public_keys() ->
    Keys = application:get_env(xsync_proto, public_keys, [none]),
    lists:map(
      fun(none) ->
              none;
         (KeyBin) ->
            [DSAEntry] = public_key:pem_decode(KeyBin),
            public_key:pem_entry_decode(DSAEntry)
      end, Keys).

%%%===================================================================
%%% Internal functions
%%%===================================================================

get_symm_ivec() ->
    application:get_env(xsync_proto, encrypt_ivec, <<"0000000000000000">>).

padding(Text) ->
    N = 16 - (byte_size(Text) rem 16),
    <<Text/binary, (binary:copy(<<N:8>>, N))/binary>>.

remove_padding(<<>>) -> <<>>;
remove_padding(CipherText) ->
    N = binary:last(CipherText),
    binary:part(CipherText, 0, byte_size(CipherText) - N).
