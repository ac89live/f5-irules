# v1.0 > iRule written and created by Abed AL-R -- 11-03-2021
# v1.1 > added the formattedstarttime global variable to check first violation time and date and unset it after sending the email notification -- 12-03-2021
# v1.2 > used 'table add' instead of table incr (because of the 180 seconds timeout) -- 13-03-2021
# v1.3 > added the 'remainder' section to substract $now time from $curtimestart time. And if it is much than 1 week then unset the $formattedstarttime variable -- 13-03-2021
# v1.4 > modified the way "getCount" vaiable get incr. it was incr +1, and now it incr by the "viocount" variable value -- 13-03-2021
# v1.5 > Used the "ASM_REQUEST_DONE" instead of "ASM_REQUEST_VIOLATION" as the ASM_REQUEST_VIOLATION was deprecated in v11.5 and replaced with ASM_REQUEST_DONE, Cont'd
# >>>>>> Although the ASM_REQUEST_VIOLATION worked in other virtual servers and not sure why in some virtual servers it didn't work, Cont'd
# >>>>>> Anyway, "ASM_REQUEST_DONE" is also doing the work

# Discription:
# This iRule should send email notification if number of violations in ASM / AWAF crossed the 100 violations in maximum 7 days
# After 7 days the counter will be reset if no violation was encountered
# If during the 7 days the counter reach the 100 violations it will send the email notification and reset the counter
# If no need to reset the counter after 7 days without any violation then you can delete lines related to "$remainder" variable
#>>>    set now [clock seconds] 
#>>>    set remainder [expr {${now} - $::curtimestart}]
#>>>	if {$remainder > 604800}{
#>>>		unset ::formattedstarttime
#>>>		unset getCount
#>>>		table delete -all -subtable "countvio"
#>>>		return
#>>>	}


when RULE_INIT {
	set static::maxRate 100
}

when ASM_REQUEST_DONE { 

set requrl [HTTP::host]	

	# Vairable "formattedstarttime" will be used later in this irule to inform the administrator in the email notification body when was the first violation was created
	# Chech if the "formattedstarttime" variable exist, if not, create it
	# I'm using here the "IST" timezone, change it to whatever your F5 machine timezone is using
	# I'm using global variables because the value of those variables should be shared across the TMMs
	if { ([info exists ::formattedstarttime]) and ($::formattedstarttime contains "IST")} {
    #log local0. "Agent11 time: $::formattedstarttime"

        set now [clock seconds] 
        set remainder [expr {${now} - $::curtimestart}]
        #log local0. "Agent22 time: $remainder"

    } else {
        set ::curtimestart [clock second]
        set ::formattedstarttime [clock format $::curtimestart]
        #log local0. "Agent33 time: $::curtimestart"
        # set "remainder" to zero o avoid errors after " $getCount < $static::maxRate " section
        set remainder 0
    }

# We'll be using the variables "srcip" amd "curtime" to create a unique variable anmed "key" to insert it later in this irule into a table named countvio, Cont'd
# in order to count violations no matter from which source IP they came from
set srcip [IP::remote_addr]
set curtime [clock second]
set hash $curtime
set key "count:$srcip:$hash"
#log local0. "Count0 is: $key"
    
	if { [ASM::violation count] > 0 } {

        table add -subtable "countvio" $key "inserted" indef
        set getCount [table keys -subtable "countvio" -count]
		set viocount [ASM::violation count]
		#log local0. "Count1 is: $getCount / $static::maxRate"
			
			# If $getCount variable is less than $static::maxRate variable then incr +1 the getCount value
			if { $getCount < $static::maxRate } {
		    
				# If remainder larger than 1 week then the variable 'formattedstarttime' is not relevant anymore and should be deleted from memory
				if {$remainder > 604800}{
					unset ::formattedstarttime
					unset getCount
					table delete -all -subtable "countvio"
					return
				}
                # Increment the value of variable "getCount" by the number of violations 
				incr getCount $viocount
				#log local0. "Count2 is: $getCount / $static::maxRate"
				return

			} else {
				# Send the email notification, But first, delete the "countvio" table enties
				table delete -all -subtable "countvio"
				set mailfrom "from@mail.com"
				set mailserv "192.168.1.1:25"
				set response0 "<font face=calibri>Dear Team</font>"
				set response1 "<font face=calibri>The website <b>$requrl</b> has exceeded the number of violations: <b>$getCount / $static::maxRate</b> since <b>$::formattedstarttime</b></font>"
				set recipient "to@mail.com"
				set conn [connect -timeout 3000 -idle 30 -status conn_status $mailserv]
				#log local0. "Agent login success"
				set data "HELO\r\nMAIL FROM: $mailfrom\r\nRCPT TO: $recipient\r\nDATA\r\nSUBJECT: Application Login Activity\r\nMIME-Version: 1.0;\r\nContent-Type: text/html;charset=iso-8859-1;\r\n\r\n\r\n$response0<p>\r\n$response1</p>\r\n\r\n.\r\n"
				set send_info [send -timeout 3000 -status send_status $conn $data]
				set recv_data [recv -timeout 3000 -status recv_status 393 $conn]
				#log local0.info $recv_data
				unset ::formattedstarttime
				close $conn
				return
			}
	}
}