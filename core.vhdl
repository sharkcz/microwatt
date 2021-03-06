library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity core is
	generic (
		SIM : boolean := false
	);
	port (
		clk          : in std_logic;
		rst          : in std_logic;

		wishbone_in  : in wishbone_slave_out;
		wishbone_out : out wishbone_master_out;

		-- Added for debug, ghdl doesn't support external names unfortunately
		registers    : out regfile;
		terminate_out : out std_ulogic
	);
end core;

architecture behave of core is
	-- fetch signals
	signal fetch1_to_fetch2: Fetch1ToFetch2Type;
	signal fetch2_to_decode1: Fetch2ToDecode1Type;

	-- decode signals
	signal decode1_to_decode2: Decode1ToDecode2Type;
	signal decode2_to_execute1: Decode2ToExecute1Type;

	-- register file signals
	signal register_file_to_decode2: RegisterFileToDecode2Type;
	signal decode2_to_register_file: Decode2ToRegisterFileType;
	signal writeback_to_register_file: WritebackToRegisterFileType;

	-- CR file signals
	signal decode2_to_cr_file: Decode2ToCrFileType;
	signal cr_file_to_decode2: CrFileToDecode2Type;
	signal writeback_to_cr_file: WritebackToCrFileType;

	-- execute signals
	signal execute1_to_execute2: Execute1ToExecute2Type;
	signal execute2_to_writeback: Execute2ToWritebackType;
	signal execute1_to_fetch1: Execute1ToFetch1Type;

	-- load store signals
	signal decode2_to_loadstore1: Decode2ToLoadstore1Type;
	signal loadstore1_to_loadstore2: Loadstore1ToLoadstore2Type;
	signal loadstore2_to_writeback: Loadstore2ToWritebackType;

	-- multiply signals
	signal decode2_to_multiply: Decode2ToMultiplyType;
	signal multiply_to_writeback: MultiplyToWritebackType;

	-- wishbone signals
	signal wishbone_data_in : wishbone_slave_out;
	signal wishbone_data_out : wishbone_master_out;
	signal wishbone_insn_in : wishbone_slave_out;
	signal wishbone_insn_out : wishbone_master_out;

	-- local signals
	signal fetch_enable: std_ulogic := '0';
	signal complete: std_ulogic;
	signal first_fetch: std_ulogic := '0';

	signal terminate: std_ulogic;
begin

	terminate_out <= terminate;

	fetch1_0: entity work.fetch1
		generic map (RESET_ADDRESS => (others => '0'))
		port map (clk => clk, rst => rst, fetch_one_in => fetch_enable,
			  e_in => execute1_to_fetch1, f_out => fetch1_to_fetch2);

	fetch2_0: entity work.fetch2
		port map (clk => clk, wishbone_in => wishbone_insn_in,
			  wishbone_out => wishbone_insn_out, f_in => fetch1_to_fetch2,
			  f_out => fetch2_to_decode1);

	decode1_0: entity work.decode1
		port map (clk => clk, f_in => fetch2_to_decode1, d_out => decode1_to_decode2);

	decode2_0: entity work.decode2
		port map (clk => clk, d_in => decode1_to_decode2, e_out => decode2_to_execute1,
			  l_out => decode2_to_loadstore1, m_out => decode2_to_multiply,
			  r_in => register_file_to_decode2, r_out => decode2_to_register_file,
			  c_in => cr_file_to_decode2, c_out => decode2_to_cr_file);

	register_file_0: entity work.register_file
		port map (clk => clk, d_in => decode2_to_register_file,
			  d_out => register_file_to_decode2, w_in => writeback_to_register_file,
			  registers_out => registers);

	cr_file_0: entity work.cr_file
		port map (clk => clk, d_in => decode2_to_cr_file, d_out => cr_file_to_decode2,
			  w_in => writeback_to_cr_file);

	execute1_0: entity work.execute1
		generic map (SIM => SIM)
		port map (clk => clk, e_in => decode2_to_execute1, f_out => execute1_to_fetch1,
			  e_out => execute1_to_execute2, terminate_out => terminate);

	execute2_0: entity work.execute2
		port map (clk => clk, e_in => execute1_to_execute2, e_out => execute2_to_writeback);

	loadstore1_0: entity work.loadstore1
		port map (clk => clk, l_in => decode2_to_loadstore1, l_out => loadstore1_to_loadstore2);

	loadstore2_0: entity work.loadstore2
		port map (clk => clk, l_in => loadstore1_to_loadstore2,
			  w_out => loadstore2_to_writeback, m_in => wishbone_data_in,
			  m_out => wishbone_data_out);

	multiply_0: entity work.multiply
		port map (clk => clk, m_in => decode2_to_multiply, m_out => multiply_to_writeback);

	writeback_0: entity work.writeback
		port map (clk => clk, w_in => execute2_to_writeback, l_in => loadstore2_to_writeback,
			  m_in => multiply_to_writeback, w_out => writeback_to_register_file,
			  c_out => writeback_to_cr_file, complete_out => complete);

	wishbone_arbiter_0: entity work.wishbone_arbiter
		port map (clk => clk, rst => rst, wb1_in => wishbone_data_out, wb1_out => wishbone_data_in,
			  wb2_in => wishbone_insn_out, wb2_out => wishbone_insn_in, wb_out => wishbone_out,
			  wb_in => wishbone_in);

	-- Only single issue until we add bypass support
	single_issue_0: process(clk)
	begin
		if (rising_edge(clk)) then
			if rst = '1' then
				first_fetch <= '1';
			else
				if first_fetch = '1' then
					fetch_enable <= '1';
					first_fetch <= '0';
				else
					fetch_enable <= complete;
				end if;
			end if;
		end if;
	end process single_issue_0;

end behave;
