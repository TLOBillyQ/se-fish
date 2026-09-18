local var_lib = {}
var_lib.var_table = {
}
	function var_lib.get_var(target_var_table, value_type, key)
		return target_var_table[key]
	end

	function var_lib.set_var(target_var_table, value_type, key, value)
		target_var_table[key] = value
	end

	function var_lib.set_list_index(target_var_table, index, value)
		target_var_table[index] = value
	end


	function var_lib.insert_list_value(target_var_table, index, value)
		table.insert(target_var_table, index, value)
	end

	function var_lib.append_list_value(target_var_table, value)
		target_var_table[#target_var_table+1] = value
	end

	function var_lib.pop_list_index(target_var_table, index)
		table.remove(target_var_table, index)
	end

	function var_lib.remove_list_value(target_var_table, value)
		for i = 1, #target_var_table do
			if target_var_table[i] == value then
				table.remove(target_var_table, i)
				break
			end
		end
	end

	function var_lib.clear_list(target_var_table)
		target_var_table = {}
	end
	
return var_lib