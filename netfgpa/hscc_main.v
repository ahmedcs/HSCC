///////////////////////////////////////////////////////////////////////////////
// 
// Author: Ahmed M. Abdelmoniem <ahmedcs982@gmail.com>
// Date: 15 MAR 2017
// Module: hscc_main.v
// Project: hscc: Hystersis Switching Congestion Control 
// Description: Applies HSCC to modify Receive window of ACKs to slow down the growth of the congestion window.             
//
///////////////////////////////////////////////////////////////////////////////
//`timescale 1ns/100ps
`timescale 1ns/1ps

module hscc_main #(
      parameter DATA_WIDTH = 64, 
      parameter CTRL_WIDTH          = 8,
      parameter NUM_OUTPUT_QUEUES   = 8,
      parameter SRAM_ADDR_WIDTH     = 19,   
      parameter NUM_OQ_WIDTH       = log2(NUM_OUTPUT_QUEUES),  //3
      parameter PKT_WORDS_WIDTH     = 8,
      parameter UDP_REG_SRC_WIDTH = 2
   )
   (

    // --- Interface to the previous stage
     /*input  [DATA_WIDTH+CTRL_WIDTH-1:0] in_data_ctrl,
     output [DATA_WIDTH+CTRL_WIDTH-1:0] out_data_ctrl,
     output                              out_wr,*/
     input                              in_wr,
     input  [CTRL_WIDTH-1:0]		in_ctrl,
     input  [DATA_WIDTH-1:0]            in_data,

     output reg                         out_wr,
     output reg [CTRL_WIDTH-1:0]	out_ctrl,
     output  [DATA_WIDTH-1:0]		out_data,

     /***********************Queue Occupany of src and dst queue*****************************/
      input [NUM_OQ_WIDTH-1:0]    	  dst_oq,
      input [NUM_OUTPUT_QUEUES-1:0]       dst_oq_full,
      input 				  dst_oq_avail,
      input 			       	  rd_dst_addr, rd_dst_oq,
      input  [SRAM_ADDR_WIDTH-1:0] 	  dst_oq_high_addr,
      input  [SRAM_ADDR_WIDTH-1:0] 	  dst_oq_low_addr,
      input  [SRAM_ADDR_WIDTH-1:0] 	  dst_num_words_left,
      input  [SRAM_ADDR_WIDTH-1:0] 	  dst_full_thresh,

      input                                pkt_stored,
      input                                pkt_dropped,
      input [PKT_WORDS_WIDTH-1:0]          stored_pkt_total_word_length,

      input                                pkt_removed,
      input [PKT_WORDS_WIDTH-1:0]          removed_pkt_total_word_length,
      input [NUM_OQ_WIDTH-1:0]             removed_oq, 
  
      //output reg [NUM_OUTPUT_QUEUES-1:0]   dst_oq_near_full,
      //output				   ctrl_protect,

      //Register Input
      input[15:0] 				 high_threshold, low_threshold, ctrl_threshold, dctcp_threshold,
      input[15:0]				 incast_window,
      input[31:0] 				 max_incast_time, min_incast_time, stat_reset_time, avg_queue_time,
      input					 adjust_window, ctrl_protect, use_dctcp, use_hscc, wnd_scale,
      /********************Queue Occupany of src and dst queue**********************************/

    // --- Misc
    input                              reset,
    input                              clk
   );

   //---------------------Functions ------------------------------
      function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
      endfunction // log2
   
   //------------------ Internal Parameter ---------------------------
   parameter MIN_PKT             = 60/CTRL_WIDTH + 1;
   parameter MAX_NUM_PKTS_WIDTH = SRAM_ADDR_WIDTH-MIN_PKT; // SRAM_WIDTH - min pkt size
   parameter MAX_WORDS_WIDTH    = SRAM_ADDR_WIDTH;   // 19
   parameter NUM_MAC_OUTPUT_QUEUES    = NUM_OUTPUT_QUEUES/2;   // # of MAC Output queues
   parameter MAX_PKT             = 2048/CTRL_WIDTH;   // allow for 2K bytes
   parameter PKTS_IN_RAM_WIDTH   = log2((2**SRAM_ADDR_WIDTH)/MIN_PKT);
   parameter WORD_IN_BYTES 	 =  CTRL_WIDTH; //8; 
   parameter MAX_BYTES_WIDTH 	 =  MAX_WORDS_WIDTH + log2(WORD_IN_BYTES);
   parameter MSS 		 =  1460; //1460;
   parameter INIT_CWND 		 =   10 * MSS; //14600
   parameter MIN_CWND 		  =  MSS / 10;
   parameter INIT_CWND_WORDS      =  INIT_CWND / WORD_IN_BYTES; // 

   localparam AVG_WIDTH 	= 5;
   localparam COUNT_SIZE 	= 12;	

   localparam NUM_STATES 	= 9;

   localparam CTRL_WORD		= 1;
   localparam WORD_1		= 2;
   localparam WORD_2		= 4;
   localparam WORD_3            = 8;
   localparam WORD_4		= 16;
   localparam WORD_5	        = 32;
   localparam WORD_6            = 64;
   localparam WORD_7            = 128;
   localparam WAIT_EOP          = 256;

   localparam MAX_WINDOW 	= 16'hFFFF; //Max window of 64K bytes
   localparam max_pkts_in_q 	= 16'hFFFF; //Max words in queue 
   
   localparam IP                = 16'h0800;
   localparam TCP                = 8'h06;
   localparam HTTP               = 16'h0050;    // port 80
   localparam IPERF               = 16'h1389;    // port 5001

    localparam	ECN_new		  = 2'b11;
    localparam	RESET_SCALE	 = 4'b0000; 
    localparam  SCALE_WORD	 = 12'h000;
   //---------------------- Wires/Regs ------------------------------
   reg 					 dst_addr_valid, dst_oq_avail_reg, is_incast;
   reg [NUM_STATES-1:0]                  state, state_next;
   reg 					 enable_avg, update_window_delayed;  
   reg                                   incast_on[NUM_OUTPUT_QUEUES-1:0], incast[NUM_OUTPUT_QUEUES-1:0]; 
   reg [31:0] 		     		 avg_timer, rtt_timer[NUM_OUTPUT_QUEUES-1:0] , incast_timer [NUM_OUTPUT_QUEUES-1:0] ;
   reg [COUNT_SIZE -1:0]		 fin_count [NUM_OUTPUT_QUEUES-1:0],  syn_count [NUM_OUTPUT_QUEUES-1:0];
   reg [COUNT_SIZE -1:0]		 new_flows[NUM_OUTPUT_QUEUES-1:0];
   reg  signed [31:0]			 cur_flows[NUM_OUTPUT_QUEUES-1:0]; 
   wire [COUNT_SIZE + AVG_WIDTH -1:0] 	 new_flows_avg[NUM_OUTPUT_QUEUES-1:0];
   reg [15:0]				 used_window[NUM_OUTPUT_QUEUES-1:0];
   reg [15:0]				 new_window_delayed;
   wire [15:0]			   	 rem_wire, div_wire, new_window;
   wire [15:0]		 		 flow_num;
   wire [MAX_WORDS_WIDTH-NUM_OQ_WIDTH-1:0]    	max_buff_ratio;
   reg [COUNT_SIZE + AVG_WIDTH + log2(INIT_CWND_WORDS)-1:0] new_flows_avg_mult [NUM_OUTPUT_QUEUES-1:0];
   reg [3:0]				 scale;
    
   reg					 update_ipchecksum, update_ecn, update_ecn_delayed;
   reg 		                         update_window;
   wire  				 tcp_syn, tcp_fin, tcp_ack, tcp_rst, single_out;
   wire [15:0]                           ether_type;
   wire [3:0]                            tcp_hdr_len;
   wire [7:0]                            ip_proto;
   wire [15:0]                           ip_len;
   wire [15:0]                           tcp_dst_port;
   wire [15:0]                           tcp_src_port;
   wire [15:0] 				 window;
   wire [15:0]				 checksum, new_checksum, ip_checksum, ip_checksumnew;
   wire [1:0]				 ECN;
   reg [1:0]				 ECN_new_delayed, ECN_delayed, ECN_new_delayed1, ECN_delayed1;
   reg [NUM_OUTPUT_QUEUES-1:0]   	 dst_oq_dctcp_full;

   reg [NUM_OQ_WIDTH-1:0]    	  	dst_oq_reg;

   reg [NUM_OQ_WIDTH-1:0]    	 	dst_port;
   reg [NUM_OUTPUT_QUEUES-1:0]    	dst_ports;
   reg [NUM_OQ_WIDTH-1:0]    	 	src_port;
   reg [NUM_OQ_WIDTH-1:0]    	 	src_port_hold;
   //reg [MAX_NUM_PKTS_WIDTH-1:0] 			num_pkts  [NUM_OUTPUT_QUEUES-1:0];
   reg [MAX_WORDS_WIDTH-1:0]    			num_words [NUM_OUTPUT_QUEUES-1:0];// [19:0]
   wire [MAX_WORDS_WIDTH+AVG_WIDTH-1:0]			avg_num_words [NUM_OUTPUT_QUEUES-1:0]; 
   reg [MAX_WORDS_WIDTH+AVG_WIDTH-1:0]			avg_num_words_delayed [NUM_OUTPUT_QUEUES-1:0]; 
   reg [SRAM_ADDR_WIDTH-1:0]   				num_words_left [NUM_OUTPUT_QUEUES-1:0];
   reg [MAX_WORDS_WIDTH-NUM_OQ_WIDTH-1:0]    		num_max_words [NUM_OUTPUT_QUEUES-1:0]; 
   reg [MAX_WORDS_WIDTH-NUM_OQ_WIDTH + AVG_WIDTH -1:0]    	num_max_words_delayed [NUM_OUTPUT_QUEUES-1:0];
   wire [MAX_WORDS_WIDTH-NUM_OQ_WIDTH + AVG_WIDTH -1:0] 	num_max_words_compare [NUM_OUTPUT_QUEUES-1:0];
   reg divide_start [19:0];

   reg  [DATA_WIDTH-1:0]		out_data_val; 
   reg [DATA_WIDTH-1:0]			in_data_delayed;

   integer 				 i, i2;
 

//------------------------ Logic ----------------------------------

   //----------------Assign Wires-------------

   //assign  update_window = (use_hscc && in_wr && state == WORD_7);
    //assign  update_window = (use_hscc && in_wr && state == WORD_7 && incast_on[src_port]);
   //Reset the Resevred bits of TCP if you will
   //assign  out_data = (wnd_scale && in_wr && state == WORD_6) ? {in_data_delayed[63:12], 4'b0000, in_data_delayed[7:0]} : in_data_delayed;

   //Set the window value to the updated version 
   assign out_data = out_data_val;

   //Set ECN if the DCTCP threshold is exceeded  
   assign  ECN = in_data[1:0];
   assign  ip_checksum = in_data[63:48];

   assign  ether_type = in_data[31:16];
   assign  ip_proto = in_data[7:0];
   assign  ip_len = in_data[63:48];
   
   assign  tcp_dst_port = in_data[31:16];
   assign  tcp_src_port = in_data[47:32];

   assign  tcp_hdr_len = in_data[15:12];
   assign  tcp_syn = in_data[1];
   assign  tcp_rst = in_data[2];
   assign  tcp_ack = in_data[4];
   assign  tcp_fin = in_data[0];

//   assign  scale = in_data[11:8];
   assign  window = in_data[63:48];
   //assign  chk_window = in_data[63:48] + scale;
   assign  checksum = in_data[47:32];

   assign new_window = used_window[src_port]>>scale;
  

   assign single_out = (dst_ports > 0) && ((dst_ports & dst_ports-1) == 0);
   //----------------State Mschine--------------  

   
   always@(*) begin
      state_next = state;
      out_data_val = in_data_delayed;
      case(state)
        /* read the input source header and get the first word */
	CTRL_WORD: begin
	  if(in_wr && in_ctrl==`IO_QUEUE_STAGE_NUM) begin             
		state_next = WORD_1;
            end
	end // case: READ_CTRL_WORD

        WORD_1: begin
           if(in_wr && in_ctrl==0)
	   begin
	      state_next = WORD_2;	
	      //$display(" %t HSCC: a packet recieved", $time);
	   end             	  
        end // case: READ_WORD_1
	
	WORD_2: begin
           if(in_wr) begin
	      if(ether_type  == IP)
		     state_next  = WORD_3;
	      else
		     state_next  = WAIT_EOP;
           end
        end

        WORD_3: begin
	   if(in_wr) begin
	      if(update_ecn) begin
		       out_data_val = {in_data_delayed[63:2], ECN_new_delayed};
	      end
              if (ip_proto == TCP) 
	      begin         
		  state_next = WORD_4;
		 //$display(" %t HSCC: TCP packet recieved proto:%x", $time, ip_proto);
	      end
              else 
		 state_next = WAIT_EOP;           	
            end
         end

         WORD_4: begin
            if (in_wr) begin	
               state_next = WORD_5;
	    end
         end

         WORD_5: begin
            if (in_wr) begin
		if(update_ipchecksum) begin
			out_data_val = {ip_checksumnew, in_data_delayed[47:0]};
		end 
               if (tcp_dst_port == HTTP || tcp_dst_port == IPERF || tcp_src_port == HTTP || tcp_src_port == IPERF)
                  state_next = WORD_6; 		     
               else 
                  state_next = WAIT_EOP;
            end
         end

         WORD_6: begin		
            if (in_wr) begin
			if (!tcp_fin && !tcp_rst && tcp_ack) 
			begin       
				    state_next = WORD_7;     
				     // synthesis translate_off
			            $display(" %t HSCC: TCP ACK packet - incast ON:%d ", $time, incast_on[src_port]);
				     // synthesis translate_on
			end
			else 
				state_next = WAIT_EOP;               
			end
         end
	
	 WORD_7: begin
        if (in_wr) begin
		  if(wnd_scale)
		  begin
			 out_data_val = {in_data_delayed[63:12], RESET_SCALE, in_data_delayed[7:0]};
			// synthesis translate_off
			$display(" %t HSCC: TCP packet recieved scale:%x", $time, wnd_scale);
		       // synthesis translate_on
		  end

	   state_next = WAIT_EOP;
           end
         end

	WAIT_EOP: begin
           if(in_wr) begin
		 if(update_window_delayed)
		 begin
			out_data_val = {new_window_delayed, new_checksum, in_data_delayed[31:0]}; 
		       // synthesis translate_off
			$display(" %t HSCCUPDATE: old window is %u new window is %u", $time, in_data_delayed[63:48], new_window_delayed);
		       // synthesis translate_on
		end
		if(in_ctrl!=0)
			state_next  = CTRL_WORD;
           end
        end

      endcase // case(state)
   end // always@ (*)

//----------------Register manipulation and keeping value-------------------

   always @(posedge clk) begin //, reset, dst_oq, dst_oq_high_addr,  dst_oq_low_addr, rd_dst_addr, pkt_stored, dst_full_thresh) begin 
 	 if((state == CTRL_WORD) && in_wr && (in_ctrl==`IO_QUEUE_STAGE_NUM) ) begin	
		src_port <= in_data[`IOQ_SRC_PORT_POS + NUM_OQ_WIDTH  - 1 : `IOQ_SRC_PORT_POS];
		dst_ports <= in_data[`IOQ_DST_PORT_POS + NUM_OUTPUT_QUEUES - 1:`IOQ_DST_PORT_POS];
	 end 
   end

   always @(posedge CLK) begin

      if(reset) begin
         state 			     <= CTRL_WORD;
	 avg_timer		     <= 0;
	 enable_avg		     <= 0;
	 scale		             <= 0;
	 for(i = 0 ; i < 8 ; i = i+1) begin: initial_regs             
	    used_window[i]	    <= MSS;
	    new_flows[i] 	    <= 0;
	    cur_flows[i]     	    <= 0;
	    syn_count[i]	    <= 0;
            fin_count[i] 	    <= 0;
	    num_words[i]   	    <= 0;
	    incast_timer[i]  	    <= 0;
	    rtt_timer[i]	    <= 0;
	    incast_on[i]	    <= 0;
	    dst_oq_dctcp_full[i]     <= 0;
	 end
      end else begin
         state			   <= state_next;
	
	 for(i = 0 ; i < NUM_OUTPUT_QUEUES ; i = i+1) begin
		 new_flows[i] <= (syn_count[i] > fin_count[i])? syn_count[i] - fin_count[i] : 0;
		 dst_oq_dctcp_full[i] <= (num_words[i] > (num_max_words[i]>>dctcp_threshold));
	 end

//Setup the used advertised window	
	 if (!adjust_window)
		used_window [src_port_hold] <= incast_window;
	 else if(divide_start[18]) begin
		if (div_wire <= INIT_CWND) begin
			if (div_wire <= MIN_CWND)
				used_window [src_port_hold] <= MIN_CWND;
			else
				used_window [src_port_hold] <= div_wire;
		end else begin
			if (div_wire <= MAX_WINDOW)
				used_window [src_port_hold] <= INIT_CWND;
			else
				used_window [src_port_hold] <= incast_window;				
		end
	end
// avg timer
	 if(avg_timer >= avg_queue_time) begin
		avg_timer 		    <= 0;
		enable_avg		    <= 1;
	 end else begin
		avg_timer 		   <= avg_timer + 1;
		enable_avg		   <= 0;
	end

//Incast Handling
	for(i = 0 ; i < NUM_OUTPUT_QUEUES ; i = i+1) begin
 	       if (rtt_timer[i]  >= stat_reset_time) begin
			//eleph_flows[i]	 <= cur_flows[i];
				syn_count[i]	 <= 0;
				fin_count[i]	 <= 0;
				rtt_timer[i]     <= 0;
            end else begin
				rtt_timer[i]		   <= rtt_timer[i] + 1;
	       end		
		/*	       
		if(incast_timer[i] == max_incast_time || (incast_timer[i] > min_incast_time && avg_num_words[i] < (num_max_words_compare[i]>>safe_threshold))) begin
			incast_on[i] <= 0;
		end else if (incast[i]) begin			
			incast_on[i] <= 1;
		end	
		*/
		if( num_words[i] < (num_max_words[i]>>low_threshold)) 
		begin			
			incast_on[i] <= 0;
			//$display("%t HSCCOFF %d: qw:%x qmax:%x left:%x ", $time, i, num_words[i], num_max_words[i]>>low_threshold, num_words_left[i] );
		end 
		else if ( num_words[i] > (num_max_words[i]>>high_threshold))
		begin
			incast_on[i] <= 1;
			//$display("%t HSCCON %d: qw:%x qmax:%x left:%x ", $time, i, num_words[i], num_max_words[i]>>high_threshold, num_words_left[i]);
		end
		

		if (incast_on[i]) begin
			incast_timer[i] <= incast_timer[i] + 1;
			if(  rtt_timer[i] > (min_incast_time>>1) ) begin 
				syn_count[i]	 <= 0;
				fin_count[i]	 <= 0;
				rtt_timer[i]	 <= 0;
			end
		end else begin
			incast_timer[i] <= 0;
		end
	end		
		

if (state == WORD_6) begin
	//Read scaling factor
	scale <= wnd_scale ? in_data[11:8] : 0;
  
        if (single_out && tcp_fin) begin // FIN - Connection Close
		   rtt_timer[dst_port]		   <= 0;
		   cur_flows[dst_port] <= cur_flows[dst_port] - 1'b1;		   
		   if(rtt_timer[dst_port] < (min_incast_time>>2) || fin_count[dst_port]==0) //FIN if within 3 times avg_timer i
			fin_count[dst_port] <= fin_count[dst_port] + 1;			
		   
	end else if (single_out && tcp_syn)   begin //SYN - Connection open	
		    rtt_timer[dst_port]		   <= 0;
		    cur_flows[dst_port] <= cur_flows[dst_port] + 1'b1;
	            if(rtt_timer[dst_port] < (min_incast_time>>2) || syn_count[dst_port]==0) //Add to SYN if within 3 times
		    	syn_count[dst_port] <= syn_count[dst_port] + 1;
		   		
	end
end	


 //----------------------- Modules ---------------------------------
//assign max_buff_ratio = (num_max_words[src_port] - (num_max_words[src_port]>>safe_threshold)); 
assign max_buff_ratio = (num_max_words[src_port] - (num_max_words[src_port]>>low_threshold)); 
assign flow_num = cur_flows[src_port] > 0 ? cur_flows[src_port] : 1;

div_gen_v2_0 div_gen_v2_0_inst1 (
		.clk(clk),
		.dividend(max_buff_ratio),
		.divisor(flow_num),
		.quotient(div_wire),
		.fractional(rem_wire)
);

calculate_tcp_checksum cal_checksum_0(.clk(clk), .old_window(window), .new_window(new_window), .old_checksum(checksum), .new_checksum(new_checksum));

calculate_ip_checksum cal_checksum_1(.clk(clk), .new_ecn(ECN_new_delayed1), .old_ecn(ECN_delayed1), .old_checksum(ip_checksum), .new_checksum(ip_checksumnew));


   
 //----------------------- Modules ---------------------------------

always @(posedge clk) begin
		case(dst_ports)
        	'h2:    dst_port  <= 'h1;
        	'h4:    dst_port  <= 'h2;
        	'h8:    dst_port  <= 'h3;
        	'h10:   dst_port  <= 'h4;
        	'h20:   dst_port  <= 'h5;
        	'h40:   dst_port  <= 'h6;
        	'h80:   dst_port  <= 'h7;
        	'h100:  dst_port  <= 'h8;
        	'h200:  dst_port  <= 'h9;
        	'h400:  dst_port  <= 'ha;
        	'h800:  dst_port  <= 'hb;
        	'h1000: dst_port  <= 'hc;
        	'h2000: dst_port  <= 'hd;
        	'h4000: dst_port  <= 'he;
        	'h8000: dst_port  <= 'hf;
		default: dst_port <= 'h0;
      		endcase
end

endmodule // rwndq_main

