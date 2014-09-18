require File.dirname(__FILE__) + '/../../concat/impl'

Puppet::Type.type(:concat_file).provide(:posix) do
    desc "Manage concat_files on Posix systems."

    defaultfor :operatingsystem => [:debian, :ubuntu]
    
    include Puppet::Util::POSIX

    mk_resource_methods

    def exists?
        return impl.exists?
    end
    
    def remove
        return impl.remove
    end
    
    def has_changed?
        return impl.has_changed?
    end

    def write
        impl.write
    end
    
    def dump
        warning impl.dump
    end
    
    def find_lost
        ConcatFileImpl.find_lost
    end

    def read
        impl.read
    end
    
    def file_content
        return impl.file_content
    end
    
    def content
        return impl.should
    end

    def uid2name(id)
        return id.to_s if id.is_a?(Symbol) or id.is_a?(String)
        return nil if id > Puppet[:maximum_uid].to_i

        begin
            user = Etc.getpwuid(id)
        rescue TypeError, ArgumentError
            return nil
        end

        if user.uid == ""
            return nil
        else
            return user.name
        end
    end

    # Determine if the user is valid, and if so, return the UID
    def name2uid(value)
        Integer(value) rescue uid(value) || false
    end

    def gid2name(id)
        return id.to_s if id.is_a?(Symbol) or id.is_a?(String)
        return nil if id > Puppet[:maximum_uid].to_i

        begin
            group = Etc.getgrgid(id)
        rescue TypeError, ArgumentError
            return nil
        end

        if group.gid == ""
            return nil
        else
            return group.name
        end
    end

    def name2gid(value)
        Integer(value) rescue gid(value) || false
    end

    def owner
        unless stat = resource.stat
            return :absent
        end

        currentvalue = stat.uid

        # On OS X, files that are owned by -2 get returned as really
        # large UIDs instead of negative ones.  This isn't a Ruby bug,
        # it's an OS X bug, since it shows up in perl, too.
        if currentvalue > Puppet[:maximum_uid].to_i
            self.warning "Apparently using negative UID (#{currentvalue}) on a platform that does not consistently handle them"
            currentvalue = :silly
        end

        currentvalue
    end

    def owner=(should)
        path = resource[:path]
        if path == nil
            path = resource[:name]
        end
        begin
            File.chown(should, nil, path)
        rescue => detail
            raise Puppet::Error, "Failed to set owner to '#{should}': #{detail}", detail.backtrace
        end
    end

    def group
        unless stat = resource.stat
            return :absent
        end

        currentvalue = stat.gid

        # On OS X, files that are owned by -2 get returned as really
        # large GIDs instead of negative ones.  This isn't a Ruby bug,
        # it's an OS X bug, since it shows up in perl, too.
        if currentvalue > Puppet[:maximum_uid].to_i
            self.warning "Apparently using negative GID (#{currentvalue}) on a platform that does not consistently handle them"
            currentvalue = :silly
        end

        currentvalue
        end

    def group=(should)
        path = resource[:path]
        if path == nil
            path = resource[:name]
        end
        begin
            File.chown(nil, should, path)
        rescue => detail
            raise Puppet::Error, "Failed to set group to '#{should}': #{detail}", detail.backtrace
        end
    end

    def mode
        if stat = resource.stat
            #info 'retr mode = ' + stat.mode.to_s
            return (stat.mode & 007777).to_s(8)
        else
            #info 'retr mode = absent'
            return :absent
        end
    end

    def mode=(value)
        #info 'change mode to ' + value.to_s
        path = resource[:path]
        if path == nil
            path = resource[:name]
        end
        begin
            File.chmod(value.to_i(8), path)
        rescue => detail
            error = Puppet::Error.new("failed to set mode #{mode} on #{resource[:path]}: #{detail.message}")
            error.set_backtrace detail.backtrace
            raise error
        end
    end
    
    def register
        path = resource[:path]
        if path == nil
            path = resource[:name]
        end
        @impl = ConcatFileImpl.register_file(resource[:name], path, resource[:header], resource[:footer])
    end

    private
    
    def impl
        #puts 'get_or_create_instance on ' + resource[:name] + ' impl=' + @impl.to_s
        return @impl
    end

end
