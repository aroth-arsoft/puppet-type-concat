require 'tempfile'

require 'puppet/util/symbolic_file_mode'
require 'puppet/util/checksums'
require 'puppet/util/diff'

Puppet::Type.newtype(:concat_file) do
    include Puppet::Util::SymbolicFileMode
	@doc = "Concats one or many concat_fragment into a single file."

    ensurable do
        defaultvalues

        newvalue(:absent) do
            path = @resource[:path]
            if path == nil
                path = @resource[:name]
            end
            File.unlink(path)
        end

        aliasvalue :purged, :absent
        aliasvalue(:false, :absent)

        defaultto :present
        aliasvalue(:file, :present)

		newvalue(:present, :event => :file_created) do
            # Make sure we're not managing the content some other way
            if property = @resource.property(:content)
                property.sync
            else
                @resource.write(:ensure)
                mode = @resource.should(:mode)
                owner = @resource.should(:owner)
                group = @resource.should(:group)
            end
		end

        def sync
            @resource.remove_existing(self.should)
            if self.should == :absent
                return :file_removed
            end

            event = super

            event
        end

        munge do |value|
            value = super(value)
            value
        end

        def change_to_s(currentvalue, newvalue)
            return super unless newvalue.to_s == "present"

            return super unless property = @resource.property(:content)

            # We know that content is out of sync if we're here, because
            # it's essentially equivalent to 'ensure' in the transaction.
            should = property.should
            if should == :absent
                is = property.retrieve
            else
                is = :absent
            end

            property.change_to_s(is, should)
        end

        def retrieve
            if provider.exists?
                property = @resource.property(:content)
                if property == nil
                    property = @resource.newattr(:content)
                    #debug "create content property"
                end
#                 currentvalue = property.retrieve
#                 #property.sync unless property.safe_insync?(currentvalue)
#                 property.sync unless property.insync?(currentvalue)
                return :present
            else
                return :absent
            end
        end
    end

    newparam(:name, :namevar => true) do
        desc <<-'EOT'
            The name to the file to manage.
        EOT
    end

    newparam(:path) do
        desc <<-'EOT'
            The path to the file to manage.  Must be fully qualified.

            On Windows, the path should include the drive letter and should use `/` as
            the separator character (rather than `\\`).
        EOT

        validate do |value|
            unless Puppet::Util.absolute_path?(value)
            fail Puppet::Error, "File paths must be fully qualified, not '#{value}'"
            end
        end

        munge do |value|
            if value == nil
                return ::File.expand_path(@resource[:name])
            else
                return ::File.expand_path(value)
            end
        end
    end

    newparam(:header) do
        desc "Content to be added to the file as header."
    end

    newparam(:footer) do
        desc "Content to be added to the file as footer."
    end
    
    def initialize(hash)
        super
        @stat = :needs_stat
    end
    def flush
        #debug "flush"
        # We want to make sure we retrieve metadata anew on each transaction.
        @parameters.each do |name, param|
            param.flush if param.respond_to?(:flush)
        end
        @stat = :needs_stat
    end

    newproperty(:mode) do
        require 'puppet/util/symbolic_file_mode'
        include Puppet::Util::SymbolicFileMode
        desc <<-EOT
            The desired permissions mode for the file, in symbolic or numeric
            notation. Puppet uses traditional Unix permission schemes and translates
            them to equivalent permissions for systems which represent permissions
            differently, including Windows.

            Numeric modes should use the standard four-digit octal notation of
            `<setuid/setgid/sticky><owner><group><other>` (e.g. 0644). Each of the
            "owner," "group," and "other" digits should be a sum of the
            permissions for that class of users, where read = 4, write = 2, and
            execute/search = 1. When setting numeric permissions for
            directories, Puppet sets the search permission wherever the read
            permission is set.

            Symbolic modes should be represented as a string of comma-separated
            permission clauses, in the form `<who><op><perm>`:

            * "Who" should be u (user), g (group), o (other), and/or a (all)
            * "Op" should be = (set exact permissions), + (add select permissions),
            or - (remove select permissions)
            * "Perm" should be one or more of:
                * r (read)
                * w (write)
                * x (execute/search)
                * t (sticky)
                * s (setuid/setgid)
                * X (execute/search if directory or if any one user can execute)
                * u (user's current permissions)
                * g (group's current permissions)
                * o (other's current permissions)

            Thus, mode `0664` could be represented symbolically as either `a=r,ug+w` or
            `ug=rw,o=r`. See the manual page for GNU or BSD `chmod` for more details
            on numeric and symbolic modes.

            On Windows, permissions are translated as follows:

            * Owner and group names are mapped to Windows SIDs
            * The "other" class of users maps to the "Everyone" SID
            * The read/write/execute permissions map to the `FILE_GENERIC_READ`,
            `FILE_GENERIC_WRITE`, and `FILE_GENERIC_EXECUTE` access rights; a
            file's owner always has the `FULL_CONTROL` right
            * "Other" users can't have any permissions a file's group lacks,
            and its group can't have any permissions its owner lacks; that is, 0644
            is an acceptable mode, but 0464 is not.
        EOT

        validate do |value|
            unless value.nil? or valid_symbolic_mode?(value)
                raise Puppet::Error, "The file mode specification is invalid: #{value.inspect}"
            end
        end

        munge do |value|
            return nil if value.nil?

            unless valid_symbolic_mode?(value)
                raise Puppet::Error, "The file mode specification is invalid: #{value.inspect}"
            end

            normalize_symbolic_mode(value)
        end

        def desired_mode_from_current(desired, current)
            current = current.to_i(8) if current.is_a? String
            symbolic_mode_to_int(desired, current, false)
        end

        # If we're not following links and we're a link, then we just turn
        # off mode management entirely.
        def insync?(currentvalue)
            if stat = @resource.stat and stat.ftype == "link" and @resource[:links] != :follow
                self.debug "Not managing symlink mode"
                return true
            else
                return super(currentvalue)
            end
        end

        def property_matches?(current, desired)
            return false unless current
            current_bits = normalize_symbolic_mode(current)
            desired_bits = desired_mode_from_current(desired, current).to_s(8)
            current_bits == desired_bits
        end

        # Ideally, dirmask'ing could be done at munge time, but we don't know if 'ensure'
        # will eventually be a directory or something else. And unfortunately, that logic
        # depends on the ensure, source, and target properties. So rather than duplicate
        # that logic, and get it wrong, we do dirmask during retrieve, after 'ensure' has
        # been synced.
        def retrieve
            @resource.stat
            super
        end

        # Finally, when we sync the mode out we need to transform it; since we
        # don't have access to the calculated "desired" value here, or the
        # "current" value, only the "should" value we need to retrieve again.
        def sync
            current = @resource.stat ? @resource.stat.mode : 0644
            set(desired_mode_from_current(@should[0], current).to_s(8))
        end

        def change_to_s(old_value, desired)
            return super if desired =~ /^\d+$/

            old_bits = normalize_symbolic_mode(old_value)
            new_bits = normalize_symbolic_mode(desired_mode_from_current(desired, old_bits))
            super(old_bits, new_bits) + " (#{desired})"
        end

        def should_to_s(should_value)
            should_value.rjust(4, "0")
        end

        def is_to_s(currentvalue)
            currentvalue.rjust(4, "0")
        end
    end
    
    newproperty(:group) do
        desc <<-EOT
            Which group should own the file.  Argument can be either a group
            name or a group ID.

            On Windows, a user (such as "Administrator") can be set as a file's group
            and a group (such as "Administrators") can be set as a file's owner;
            however, a file's owner and group shouldn't be the same. (If the owner
            is also the group, files with modes like `0640` will cause log churn, as
            they will always appear out of sync.)
        EOT

        validate do |group|
            raise(Puppet::Error, "Invalid group name '#{group.inspect}'") unless group and group != ""
        end

        def insync?(current)
            # We don't want to validate/munge groups until we actually start to
            # evaluate this property, because they might be added during the catalog
            # apply.
            @should.map! do |val|
                provider.name2gid(val) or raise "Could not find group #{val}"
            end

            @should.include?(current)
        end

        # We want to print names, not numbers
        def is_to_s(currentvalue)
            provider.gid2name(currentvalue) || currentvalue
        end

        def should_to_s(newvalue)
            provider.gid2name(newvalue) || newvalue
        end
    end
    
    newproperty(:owner) do
        include Puppet::Util::Warnings
        desc <<-EOT
            The user to whom the file should belong.  Argument can be a user name or a
            user ID.

            On Windows, a group (such as "Administrators") can be set as a file's owner
            and a user (such as "Administrator") can be set as a file's group; however,
            a file's owner and group shouldn't be the same. (If the owner is also
            the group, files with modes like `0640` will cause log churn, as they
            will always appear out of sync.)
        EOT

        def insync?(current)
            # We don't want to validate/munge users until we actually start to
            # evaluate this property, because they might be added during the catalog
            # apply.
            @should.map! do |val|
                provider.name2uid(val) or raise "Could not find user #{val}"
            end

            return true if @should.include?(current)

            unless Puppet.features.root?
                warnonce "Cannot manage ownership unless running as root"
                return true
            end

            false
        end

        # We want to print names, not numbers
        def is_to_s(currentvalue)
            provider.uid2name(currentvalue) || currentvalue
        end

        def should_to_s(newvalue)
            provider.uid2name(newvalue) || newvalue
        end
    end
    
    # Specify which checksum algorithm to use when checksumming
    # files.
    newparam(:checksum) do
        include Puppet::Util::Checksums
        desc "The checksum type to use when determining whether to replace a file's contents.

            The default checksum type is md5."

        newvalues "md5", "md5lite", "mtime", "ctime", "none"

        defaultto :md5

        def sum(content)
            type = value || :md5 # because this might be called before defaults are set
            "{#{type}}" + send(type, content)
        end

        def sum_file(path)
            type = value || :md5 # because this might be called before defaults are set
            method = type.to_s + "_file"
            "{#{type}}" + send(method, path).to_s
        end

        def sum_stream(&block)
            type = value || :md5 # same comment as above
            method = type.to_s + "_stream"
            checksum = send(method, &block)
            "{#{type}}#{checksum}"
        end
    end
    
    newproperty(:content) do
        include Puppet::Util::Diff
        include Puppet::Util::Checksums

        attr_reader :actual_content

        desc <<-'EOT'
            The desired contents of a file, as a string. This attribute is mutually
            exclusive with `source` and `target`.

            Newlines and tabs can be specified in double-quoted strings using
            standard escaped syntax --- \n for a newline, and \t for a tab.

            With very small files, you can construct content strings directly in
            the manifest...

                define resolve(nameserver1, nameserver2, domain, search) {
                    $str = "search $search
                        domain $domain
                        nameserver $nameserver1
                        nameserver $nameserver2
                        "

                    file { "/etc/resolv.conf":
                    content => "$str",
                    }
                }

            ...but for larger files, this attribute is more useful when combined with the
            [template](http://docs.puppetlabs.com/references/latest/function.html#template)
            function.
        EOT

        # Store a checksum as the value, rather than the actual content.
        # Simplifies everything.
        munge do |value|
            #debug "munging content value #{value}"
            if value == :absent
                value
            elsif checksum?(value)
                # XXX This is potentially dangerous because it means users can't write a file whose
                # entire contents are a plain checksum
                value
            else
                @actual_content = value
                resource.parameter(:checksum).sum(value)
            end
        end

        # Checksums need to invert how changes are printed.
        def change_to_s(currentvalue, newvalue)
            if currentvalue == :absent
                return "defined content as '#{newvalue}'"
            elsif newvalue == :absent
                return "undefined content from '#{currentvalue}'"
            else
                return "content changed '#{currentvalue}' to '#{newvalue}'"
            end
        end

        def checksum_type
            resource[:checksum]

            if result =~ /^\{(\w+)\}.+/
                return $1.to_sym
            else
                return result
            end
        end

        def length
            (actual_content and actual_content.length) || 0
        end

        def content
            provider.content
            #self.should
        end
        
        def insync?(current)
            return false if current == :absent
            #provider.dump
            #provider.find_lost
            ret = @resource.has_changed?(:content) ? false : true
            resource_path = @resource[:path]
            if resource_path == nil
                resource_path = @resource[:name]
            end
            
            #debug "insync? content #{ret} show_diff=#{Puppet[:show_diff]}"
            if ! ret and Puppet[:show_diff]
                write_temporarily do |path|
                    notice "\n" + diff(resource_path, path)
                end
            end
            ret
        end

        def retrieve
            return :absent unless stat = @resource.stat

            @actual_content = provider.read
            @content = provider.read
            begin
                self.should = resource.parameter(:checksum).sum(@content)
                ret = resource.parameter(:checksum).sum(@actual_content)
                debug "retrieve content got #{ret} should #{self.should}"
                ret
            rescue => detail
                raise Puppet::Error, "Could not read #{ftype} #{@resource.title}: #{detail}"
            end
        end

        # Make sure we're also managing the checksum property.
        def should=(value)
            @resource.newattr(:checksum) unless @resource.parameter(:checksum)
            super
        end

        def write_temporarily
            tempfile = Tempfile.new("puppet-file")
            tempfile.open

            write(tempfile)

            tempfile.close

            yield tempfile.path

            tempfile.delete
        end

        def write(file)
            chunk = provider.content
            #debug "write content #{chunk}"
            file.print chunk
            resource.parameter(:checksum).sum(chunk)
        end

        # Just write our content out to disk.
        def sync
            #debug 'content sync'
            # We're safe not testing for the 'source' if there's no 'should'
            # because we wouldn't have gotten this far if there weren't at least
            # one valid value somewhere.
            @resource.write(:content)
        end

    end
    
#    def refresh
#        #debug 'refresh'
#        super
#    end

#     def retrieve
#         # Our ensure property knows how to retrieve everything for us.
#         if obj = @parameters[:ensure]
#             return obj.retrieve
#         else
#             return {}
#         end
#     end
    
    # Remove any existing data.  This is only used when dealing with
    # links or directories.
    def remove_existing(should)
        return unless s = stat

        path = self[:path]
        if path == nil
            path = self[:name]
        end
        case s.ftype
        when "directory"
            notice "Not removing directory"
            return
        when "link", "file"
            debug "Removing existing #{s.ftype} for replacement with #{should}"
            ::File.unlink(path)
        else
            self.fail "Could not back up files of type #{s.ftype}"
        end
        @stat = :needs_stat
        true
    end
    
    def has_changed?(property)
        return provider.has_changed?
    end
    
    # Write out the file.  Requires the property name for logging.
    # Write will be done by the content property, along with checksum computation
    def write(property)
        #remove_existing(:file)

        return_event = stat ? :file_changed : :file_created
        path = self[:path]
        if path == nil
            path = self[:name]
        end

        mode = self.should(:mode) # might be nil
        umask = mode ? 000 : 022
        mode_int = mode ? symbolic_mode_to_int(mode, 0644) : nil

        content_checksum = Puppet::Util.withumask(umask) { 
            provider.write
        }
        property_fix

        return_event
    end

    # There are some cases where all of the work does not get done on
    # file creation/modification, so we have to do some extra checking.
    def property_fix
        properties.each do |thing|
            next unless [:mode, :owner, :group].include?(thing.name)

            # Make sure we get a new stat objct
            @stat = :needs_stat
            currentvalue = thing.retrieve
            thing.sync unless thing.safe_insync?(currentvalue)
        end
    end

    # Still need the generate method, to create a dummy File
    # resource to keep the recursive directories from removing
    # out concat_file targets
    def generate
        #debug 'generate'

        #return nil
        path = self[:path]
        if path == nil
            path = self[:name]
        end
        existing_file_res = catalog.resource(:file, path)
        if !existing_file_res
            #_ensure = self[:ensure] == :present ? :file : :absent
            _ensure = self[:ensure]
            filetype = Puppet::Type.type(:file)
            fileparams = {:name => path, 
                            :ensure => _ensure,
                            :backup => false,
                            :checksum => :none
                         }
            if self[:mode]
                fileparams[:mode] = self[:mode]
            end
            if self[:owner]
                fileparams[:owner] = self[:owner]
            end
            if self[:group]
                fileparams[:group] = self[:group]
            end
            file_res = filetype.new(fileparams)
            #debug "resource file does not exist yet -> generate it with #{_ensure.to_s}"
            #debug 'generated: ' + file_res.inspect
            result = [file_res]
        else
            #debug 'resource file already exists'
            result = nil
        end
        result
    end

    # Stat our file.  Depending on the value of the 'links' attribute, we
    # use either 'stat' or 'lstat', and we expect the properties to use the
    # resulting stat object accordingly (mostly by testing the 'ftype'
    # value).
    #
    # We use the initial value :needs_stat to ensure we only stat the file once,
    # but can also keep track of a failed stat (@stat == nil). This also allows
    # us to re-stat on demand by setting @stat = :needs_stat.
    def stat
        return @stat unless @stat == :needs_stat

        path = self[:path]
        if path == nil
            path = self[:name]
        end
        @stat = begin
            ::File.stat(path)
        rescue Errno::ENOENT => error
            nil
        rescue Errno::EACCES => error
            warning "Could not stat; permission denied"
            nil
        end
    end
    autorequire(:file) do
        req = []
        path = self[:path]
        if path == nil
            path = self[:name]
        end
        req << path

        info 'autorequire file req=' + req.inspect
        req
    end

    # Autorequire the nearest ancestor directory found in the catalog.
    autorequire(:concat_fragment) do
        debug 'autorequire concat_fragment'
        #raise 'autorequire concat_file'
        req = []
        provider.register
        catalog.resources.each do |r|
            if r.is_a?(Puppet::Type.type(:concat_fragment))
                if r[:target] == self[:name]
                    #info 'autorequire concat_file add ' + r.to_s
                    req.push(r[:name])
                elsif r[:parent] == self[:name]
                    #info 'autorequire concat_file add ' + r.to_s
                    req.push(r[:name])
                else
                    #info 'autorequire concat_file ignore ' + r.to_s
                end
            end
        end
        info 'autorequire concat_fragment req=' + req.inspect
        req
    end

	# Provide an external hook.  Yay breaking out of APIs.
	def exists?
		provider.exists?
	end
end
