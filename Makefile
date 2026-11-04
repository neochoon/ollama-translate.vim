VADER_DIR := .vader-vim
VADER_URL := https://github.com/junegunn/vader.vim

.PHONY: test
test:
	@if [ ! -d $(VADER_DIR) ]; then \
		git clone --depth 1 $(VADER_URL) $(VADER_DIR); \
	fi
	vim -Nu NONE -N -c "set rtp+=$(VADER_DIR)" -c "set rtp+=." \
		-c "exe 'source' '$(VADER_DIR)/plugin/vader.vim'" \
		-c "Vader! tests/*.vader"
