REBAR3=_build/rebar3/rebar3

all: $(REBAR3)
	$(REBAR3) compile

rel: $(REBAR3)
	$(REBAR3) as prod release -n fireplace

tar: $(REBAR3)
	HIPE=1 $(REBAR3) as prod tar -n fireplace

shell: $(REBAR3)
	$(REBAR3) shell

clean: $(REBAR3)
	rm -rf _build/default/lib/*/ebin/*.beam
	$(REBAR3) clean

relock: $(REBAR3)
	$(REBAR3) upgrade

client: $(REBAR3)
	$(REBAR3) release -n xsync_client

_build/rebar3/rebar3:
	mkdir _build; git clone https://github.com/erlang/rebar3.git  _build/rebar3; (cd _build/rebar3; git checkout 3.6.2; ./bootstrap)
