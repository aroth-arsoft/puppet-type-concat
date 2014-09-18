#!/usr/bin/ruby

class ConcatFileImpl
    @@files = {}
    @@fragments = {}
    @@missing_fragments = {}
    @name = nil
    @path = nil
    @root = {}
    @content = nil
    @file_content = nil
    @owner = nil
    @group = nil
    @mode = nil
    @stat = nil

    attr_accessor :name
    attr_accessor :owner
    attr_accessor :group
    attr_accessor :mode
    
    class Fragment
        @parent = nil
        @parent_ref = nil
        @name = nil
        @childs = {}
        @header = nil
        @footer = nil
        @content = nil

        attr_accessor :name
        attr_accessor :parent
        attr_accessor :parent_ref
        attr_accessor :order
        attr_accessor :header
        attr_accessor :footer
        attr_accessor :content
        
        def initialize(name, parent_ref, order)
            @parent_ref = parent_ref
            @order = order
            @name = name
            @childs = {}
            @header = nil
            @footer = nil
            @content = nil
            
            # try to initialize the parent reference immediately (when possible)
            reconnect
        end
        
        def reconnect
            if @parent_ref != nil
                @parent = ConcatFileImpl.get_fragment(@parent_ref)
                if @parent
                    @parent.add_child(self)
                else
                    ConcatFileImpl.add_missing_fragment(@parent_ref, @name)
                    #puts "Unable to reconnect #{@name} to #{@parent_ref}"
                end
            else
                @parent = nil
            end
        end

        def add_child(child)
            #puts "add_child #{@name} child=#{child.name}"
            if not @childs.has_key?(child.order)
                @childs[child.order] = {}
            end

            @childs[child.order][child.name] = child

            # reset the internal state, since we no not know yet
            reset_content()
            return true
        end
        
        def remove_child(child)
            if @childs.has_key?(child.order)
                del @childs[child.order][child.name]
            end
            if @childs[child.order].empty?
                del @childs[child.order]
            end
        end
        
        def find_child(fragment_name)
            @childs.each do |order, fragment_dict|
                #puts "search fragment #{@name} for #{fragment_name}"
                fragment_dict.each do |current_fragment_name, current_fragment_obj|
                    #puts "check child #{current_fragment_name} vs #{fragment_name}"
                    if current_fragment_name == fragment_name
                        return current_fragment_obj
                    else
                        result = current_fragment_obj.find_child(fragment_name)
                        if result
                            return result
                        end
                    end
                end
            end
            return nil
        end
        
        def get_direct_childs()
            ret = []
            #puts "get_direct_childs for #{@name}"
            @childs.each do |order, fragment_dict|
                #puts "search fragment #{@name} for #{fragment_name}"
                fragment_dict.each do |current_fragment_name, current_fragment_obj|
                    #puts "get_direct_childs for #{@name} add #{current_fragment_name}"
                    ret << current_fragment_name
                end
            end
            return ret
        end

        def content()
            if @content == nil
                @content = ''

                if @header != nil
                    @content += @header
                end
                #puts 'content before childs ' + @content
                @childs.sort_by { |order, fragment_dict| order }.each do |order, fragment_dict|
                    fragment_dict.sort_by { |fragment_name, fragment| fragment_name }.each do |fragment_name, fragment|
                        child_content = fragment.content()
                        #puts "child content #{fragment_name}=#{child_content}"
                        @content += child_content
                    end
                end

                if @footer != nil
                    @content += @footer
                end
                #puts "got content for #{@name}=#{@content}"
            end
            return @content
        end
        
        def reset_content()
            p = @parent
            while p != nil
                p.content = nil
                p = p.parent
            end
        end

        def set(header=nil, footer=nil)

            @header = header
            @footer = footer
            if @parent == nil and @parent_ref != nil
                @parent = ConcatFileImpl.get_fragment(@parent_ref)
                if @parent
                    @parent.add_child(self)
                end
            end
            #puts "child #{@name} set parent_ref=#{@parent_ref} parent=#{parent} order=#{@order} header=#{header} footer=#{footer}"
        end
        
        def dump(level)
            ret = " "*(level * 2)
            header_str = @header ? @header.to_s.gsub(/\n/,'\\n') : 'nil'
            footer_str = @footer ? @footer.to_s.gsub(/\n/,'\\n') : 'nil'
            parent_ref_str = @parent_ref ? @parent_ref.to_s : 'nil'
            ret = ret + "+#{@name} parent_ref=#{parent_ref_str} hdr=\"#{header_str}\" ftr=\"#{footer_str}\"\n"

            @childs.sort_by { |order, fragment_dict| order }.each do |order, fragment_dict|
                fragment_dict.sort_by { |fragment_name, fragment| fragment_name }.each do |fragment_name, fragment|
                    ret = ret + fragment.dump(level + 1)
                end
            end
            return ret
        end
    end

    def initialize(name, path, header=nil, footer=nil)
        @name = name
        @path = path
        @root = Fragment.new(name, nil, 0)
        @@fragments[name] = @root
        @root.set(header, footer)
        #puts "register_fragment #{name} for file"
        @has_changed = nil
    end

    def self.get_instance(name)
        if @@files.has_key?(name)
            ret = @@files[name]
        else
            ret = nil
        end
        return ret
    end
    
    def self.register_file(name, path, header=nil, footer=nil)
        #puts "register_file #{name} as #{path}"
        ret = ConcatFileImpl.new(name, path, header, footer)
        @@files[name] = ret
        return ret
    end

    def self.register_fragment(name, parent_ref, order)
        ret = Fragment.new(name, parent_ref, order)
        @@fragments[name] = ret
        if @@missing_fragments.has_key?(name)
            #puts "register_fragment #{name} (which was missing), parent=#{parent_ref} order=#{order}"
            #puts "register_fragment #{name} missing=#{@@missing_fragments[name].to_s}"
            @@missing_fragments[name].each do |fragment_user_name|
                fragment = @@fragments[fragment_user_name]
                fragment.reconnect
                #puts "recovered missing link from #{fragment_user_name} to #{name}"
            end
            @@missing_fragments.delete(name)
        else
            #puts "register_fragment #{name}, parent=#{parent_ref} order=#{order}"
        end
        #self.dump
        return ret
    end
    
    def dump
        if @name != @path 
            ret = "#{@path} aka #{@name} = {\n"
        else
            ret = "#{@name} = {\n"
        end
        ret = ret + @root.dump(1)
        ret = ret + "}\n"
        return ret
    end
    
    def self.dump
        puts "files:"
        @@files.each do |name, instance|
            puts "  #{name} -> #{instance}"
        end
        puts "fragments:"
        @@fragments.each do |name, instance|
            puts "  #{name} parent_ref=#{instance.parent_ref} order=#{instance.order} parent=#{instance.parent}"
        end
        puts "tree:"
        @@files.each do |name, instance|
            puts instance.dump
        end
        return nil
    end
    
    def self.find_lost
        puts "lost fragments:"
        @@fragments.each do |name, instance|
            parent_ref = instance.parent_ref
            if parent_ref == nil
                if not @@files.has_key?(name)
                    puts "  #{name} parent_ref=<nil> order=#{instance.order} parent=#{instance.parent}"
                end
            else
                if not @@fragments.has_key?(parent_ref)
                puts "  #{name} parent_ref=#{parent_ref} (unknown) order=#{instance.order} parent=#{instance.parent}"
                end
            end
        end
        return nil
    end

    def self.get_fragment(name)
        #puts "get_fragment #{name}"
        if @@fragments.has_key?(name)
            ret = @@fragments[name]
        else
            ret = nil
        end
        return ret
    end

    def self.add_missing_fragment(name_of_missing, name_of_user)
        #puts "add_missing_fragment #{name_of_missing} user by #{name_of_user}"
        if @@missing_fragments.has_key?(name_of_missing)
            @@missing_fragments[name_of_missing] << name_of_user
        else
            @@missing_fragments[name_of_missing] = [ name_of_user ]
        end
    end
    

    def find_fragment(parent)
        if parent == nil
            return @root
        else
            return @root.find_child(parent)
        end
    end

    def add_fragment(parent, order, fragment_name, header=nil, footer=nil)
        fragment = find_fragment(parent)
        if fragment == nil
            return false
        else
            new_fragment = Fragment.new(fragment_name, fragment, order)
            new_fragment.header = header
            new_fragment.footer = footer

            fragment.add_child(new_fragment)
            @has_changed = nil
            @content = nil
            return true
        end
    end

    def get_childs(parent)
        #puts "get_childs for #{parent}"
        if parent == nil
            return @root.get_direct_childs
        else
            child = @root.find_child(parent)
            if child
                return child.get_direct_childs
            else
                return []
            end
        end
    end
    
    def has_changed?()
        if @has_changed == nil
            @has_changed = (file_content() != content()) ? true : false
        end
        return @has_changed
    end
    
    def self.write_all()
        @@files.each do |name, instance|
            instance.write()
        end
    end
    
    def exists?()
        stat
        @stat ? true : false
    end
    
    def write()
        stat

        if has_changed?
            #puts "ConcatFileImpl[#{@name}] has_changed -> write"
            File.open(@path, 'wb') do |f|
                f.write(content())
            end
            @has_changed = false
        else
            #puts "ConcatFileImpl[#{@name}] hasnt_changed"
            true
        end
    end
    
    def read()
        file_content()
    end

    def should()
        content()
    end
    
    def header()
        return @root.header
    end
    def header=(val)
        @root.header = val
    end
    
    def footer()
        return @root.footer
    end
    def footer=(val)
        @root.footer = val
    end
    
    private
    def stat()
        if @stat == nil
            if File.exists?(@path)
                @stat = File.stat(@path)
            else
                @stat = nil
            end
        end
        return @stat
    end

    def file_content()
        if @file_content == nil
            if File.exists?(@path)
                file = File.open(@path, "rb")
                @file_content = file.read
                file.close
            end
        end
        return @file_content
    end
    
    def content()
        return @root.content()
    end
end

