%%
%% This file is part of Triq - Trifork QuickCheck
%%
%% Copyright (c) 2010 by Trifork
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%  
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

-module(triq_domain).

-include("triq_domain.hrl").

%% generators
-export([list/1, tuple/1, int/0, real/0, sized/2, elements/1, glet/2, any/0, atom/0]).

%% using a generator
-export([generate/2, generates/2, elem_gen/2]).

%% generator for lists 
list(ElemGen) ->
    #?DOM{kind={list,ElemGen},
	generate   = fun(#?DOM{kind={list,EG}},GS) -> 
				Len = random:uniform(1+ (GS div 3))-1,
				generate_list(Len, EG, GS)
		     end,
	generates  = fun(#?DOM{kind={list,EG}},Value) when is_list(Value) -> 
			     lists:all(fun(Elem) -> generates(EG, Elem) end, Value);
			(_,_) -> false
		     end}.


%% support function for generate({gen_list, ...})
generate_list(Len,_,_) when Len =< 0 ->
    [];
generate_list(Len,_,0) ->
    [];
generate_list(Len,EG,GS) ->
    [generate(EG,GS-1) | generate_list(Len-1, EG, GS-1)].



tuple(ElemGen) ->
    #?DOM{kind={tuple,ElemGen},
	generate   = fun(#?DOM{kind={tuple,EG}},GS) -> 
				Len = random:uniform(1+ (GS div 3))-1,
				list_to_tuple(generate_list(Len, EG, GS))
		     end,
	generates  = fun(#?DOM{kind={list,EG}},Value) when is_tuple(Value) -> 
			     lists:all(fun(Elem) -> generates(EG, Elem) end, 
				       tuple_to_list(Value));
			(_,_) -> false
		     end}.

elem_gen(_, #?DOM{kind={list,ElemGen}}) ->
    ElemGen;
elem_gen(_, #?DOM{kind={tuple,ElemGen}}) ->
    ElemGen;
elem_gen(N, Gen) when is_tuple(Gen), N > 0, tuple_size(Gen) >= N ->
    element(N,Gen).

generate_int(_,GS) ->
    random:uniform(GS) - (GS div 2).

int() -> 
    #?DOM{kind=int,
	 generate  = fun generate_int/2,
	 generates = fun(_,Val) -> is_integer(Val) end
	}.

real() -> 
    #?DOM{kind=real,
	 generate  = fun(_,GS) -> (random:uniform()*GS) - (GS / 2) end,
	 generates = fun(_,Val) -> is_float(Val) end
	}.

boolean() -> 
    #?DOM{kind=int,
	  generate  = fun(_,_) -> random:uniform(2) == 1 end,
	  generates = fun(_,true) -> true; (_,false) -> true end
	 }.

rand(Min,Max,GS) ->
    Val = random:uniform(GS)-1+Min,
    if Val =< Max -> Val;
       true -> Max
    end.
	

atom() -> 
    #?DOM{kind=atom,
	  generate  = fun(_,GS) -> erlang:list_to_atom(generate(list(char()), rand(0,255,GS))) end,
	  generates = fun(_,Val) -> is_integer(Val) end
	 }.

char() -> 
    #?DOM{kind=char,
	  generate  = fun(_,GS) -> random:uniform(256)-1 end,
	  generates = fun(_,Val) -> (Val >= 0) and (Val < 256)  end
	 }.

glet(Gen1,FG2) -> 
    #?DOM{kind={glet,Gen1,FG2},
	 generate  = fun(#?DOM{kind={glet,G1,G2}},GS) -> 
			     Va = generate(G1, GS),
			     G = G2(Va),
			     generate(G,GS)
		     end,
	 generates = fun(#?DOM{kind={glet,_G1,_G2}},_Val) -> true end % urgh!
	}.

generate(#?DOM{kind=any}=Dom,GS) ->
    case random:uniform(6) of
	1 -> generate(int(),GS div 2);
	2 -> generate(real(),GS div 2);
	3 -> generate(list(Dom),GS div 2);
	4 -> generate(tuple(Dom),GS div 2);
	5 -> generate(boolean(),GS div 2);
	6 -> generate(atom(),GS div 2)
    end;

generate({call, Mod, Fun, Args},GS) 
  when is_atom(Mod), is_atom(Fun), is_list(Args) ->
    generate (apply(Mod,Fun,Args), GS);


%%
%% This is the heart of the random structure generator
%%
generate(Gen=#?DOM{generate=GenFun}, GS) ->
    GenFun(Gen,GS);

%%
%% A tuple is generated by generating each element
%%
generate({}, _) -> {};
generate(T,GS) when is_tuple(T) ->
    TList = erlang:tuple_to_list(T),
    GList = lists:map(fun(TE) -> generate(TE,GS) end, TList),
    erlang:list_to_tuple(GList);

%%
%% for Lists, we traverse down the list and generate 
%% each head
%%
generate([], _) -> [];
generate([H|T], GS) -> [generate(H,GS)|generate(T,GS)];

%%
%% simple values that generate themselves
%%
generate(V,_) when is_atom(V);
		   is_number(V);
		   is_list(V);
		   is_function(V)
		   ->
    V.


%%
%% the generates/2 tests if a given 
%% simplification actually is within
%% the domain of the generator
%%

generates(Gen=#?DOM{generates=GensFun}, GS) ->
    GensFun(Gen,GS);

%% any value generates itself
generates(V,V) ->
    true;

%% tuples are special
generates(TGen,TVal) when is_tuple(TGen), 
			  is_tuple(TVal), 
			  tuple_size(TGen) == tuple_size(TVal) ->
    
    lists:all(fun({Gen,Val}) -> generates(Gen,Val) end,
	      lists:zip( tuple_to_list(TGen),
			 tuple_to_list(TVal) ));

%% otherwise, .. false
generates(_,_) ->
    false.



sized(Size,Gen) ->
    #?DOM{kind={sized, Size, Gen}}.

elements([]) -> undefined;
elements(L) when is_list(L) ->
    #?DOM{kind={elements,L,length(L)}, 
	 generate=fun(#?DOM{kind={elements,L2,Len}},_GS) ->			  
			  lists:nth(random:uniform(Len), L2)
		  end,
	 generates=fun(#?DOM{kind={elements,L2,_Len}},Value) ->
			   lists:member(Value,L2)
		   end}.


any()  ->
    #?DOM{kind=any, generates=fun(_,_) -> true end}.



