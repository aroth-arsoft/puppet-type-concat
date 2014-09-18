require 'puppet/file_serving/content'
require 'puppet/file_serving/metadata'

Puppet::Type.newtype(:concat_fragment) do
	@doc = "Manage the Debian/Ubuntu alternatives."

    ensurable do
        defaultvalues

		newvalue(:present) do
			provider.create
		end

		newvalue(:absent) do
			#provider.destroy
		end
        
        defaultto :present

        munge do |value|
            value = super(value)
            value
        end

        def retrieve
            if source = @resource.parameter(:source)
                #info 'fragment retrieve with source'
                provider.apply(source.content, nil)
            else
                #info 'fragment retrieve content only'
                if @resource[:header] != nil or @resource[:footer] != nil
                    provider.apply(@resource[:header], @resource[:footer])
                else
                    provider.apply(@resource[:content], nil)
                end
            end
            return @resource.should(:ensure)
        end
    end

    newparam(:name, :namevar => true) do
        desc "The name of the module to be managed."
    end

    newparam(:target) do
        desc "The name of the target file."
    end

    newparam(:order) do
        desc "Order number to sort the fragments."
    end

    newparam(:parent) do
        desc "name of the parent fragment (used for ordering)"
    end

    newparam(:content) do
        desc "Content of the fragment."
    end

    newparam(:header) do
        desc "Content to be added to the beginning."
    end

    newparam(:footer) do
        desc "Content to be added to the end."
    end

    # Copy files from a local or remote source.  This state *only* does any work
    # when the remote file is an actual file; in that case, this state copies
    # the file down.  If the remote file is a dir or a link or whatever, then
    # this state, during retrieval, modifies the appropriate other states
    # so that things get taken care of appropriately.
    newparam(:source) do
        include Puppet::Util::Diff

        attr_accessor :source, :local
        desc <<-'EOT'
            A source file, which will be copied into place on the local system.
            Values can be URIs pointing to remote files, or fully qualified paths to
            files available on the local system (including files on NFS shares or
            Windows mapped drives). This attribute is mutually exclusive with
            `content` and `target`.

            The available URI schemes are *puppet* and *file*. *Puppet*
            URIs will retrieve files from Puppet's built-in file server, and are
            usually formatted as:

            `puppet:///modules/name_of_module/filename`

            This will fetch a file from a module on the puppet master (or from a
            local module when using puppet apply). Given a `modulepath` of
            `/etc/puppetlabs/puppet/modules`, the example above would resolve to
            `/etc/puppetlabs/puppet/modules/name_of_module/files/filename`.

            Unlike `content`, the `source` attribute can be used to recursively copy
            directories if the `recurse` attribute is set to `true` or `remote`. If
            a source directory contains symlinks, use the `links` attribute to
            specify whether to recreate links or follow them.

            Multiple `source` values can be specified as an array, and Puppet will
            use the first source that exists. This can be used to serve different
            files to different system types:

                file { "/etc/nfs.conf":
                source => [
                    "puppet:///modules/nfs/conf.$host",
                    "puppet:///modules/nfs/conf.$operatingsystem",
                    "puppet:///modules/nfs/conf"
                ]
                }

            Alternately, when serving directories recursively, multiple sources can
            be combined by setting the `sourceselect` attribute to `all`.
        EOT

        validate do |sources|
            sources = [sources] unless sources.is_a?(Array)
            sources.each do |source|
            next if Puppet::Util.absolute_path?(source)

            begin
                uri = URI.parse(URI.escape(source))
            rescue => detail
                self.fail "Could not understand source #{source}: #{detail}"
            end

            self.fail "Cannot use relative URLs '#{source}'" unless uri.absolute?
            self.fail "Cannot use opaque URLs '#{source}'" unless uri.hierarchical?
            self.fail "Cannot use URLs of type '#{uri.scheme}' as source for fileserving" unless %w{file puppet}.include?(uri.scheme)
            end
        end

        SEPARATOR_REGEX = [Regexp.escape(File::SEPARATOR.to_s), Regexp.escape(File::ALT_SEPARATOR.to_s)].join

        munge do |sources|
            sources = [sources] unless sources.is_a?(Array)
            sources.map do |source|
                source = source.sub(/[#{SEPARATOR_REGEX}]+$/, '')

                #info "munge source #{source}"
                if Puppet::Util.absolute_path?(source)
                    URI.unescape(Puppet::Util.path_to_uri(source).to_s)
                else
                    source
                end
            end
        end

        def change_to_s(currentvalue, newvalue)
            # newvalue = "{md5}#{@metadata.checksum}"
            if @resource.property(:ensure).retrieve == :absent
                return "creating from source #{metadata.source} with contents #{metadata.checksum}"
            else
                return "replacing from source #{metadata.source} with contents #{metadata.checksum}"
            end
        end

        def checksum
            metadata && metadata.checksum
        end

        # Look up (if necessary) and return remote content.
        def content
            return @content if @content
            raise Puppet::DevError, "No source for content was stored with the metadata" unless metadata.source

            unless tmp = Puppet::FileServing::Content.indirection.find(metadata.source, :environment => resource.catalog.environment)
                fail "Could not find any content at %s" % metadata.source
            end
            #debug 'fragment get content from source'
            @content = tmp.content
        end

        def found?
            ! (metadata.nil? or metadata.ftype.nil?)
        end

        attr_writer :metadata

        # Provide, and retrieve if necessary, the metadata for this file.  Fail
        # if we can't find data about this host, and fail if there are any
        # problems in our query.
        def metadata
            return @metadata if @metadata
            return nil unless value
            #debug 'fragment get metadata from source'
            value.each do |source|
                begin
                    if data = Puppet::FileServing::Metadata.indirection.find(source, :environment => resource.catalog.environment)
                    @metadata = data
                    @metadata.source = source
                    break
                    end
                rescue => detail
                    fail detail, "Could not retrieve file metadata for #{source}: #{detail}"
                end
            end
            fail "Could not retrieve information from environment #{resource.catalog.environment} source(s) #{value.join(", ")}" unless @metadata
            @metadata
        end

        def local?
            found? and scheme == "file"
        end

        def full_path
            Puppet::Util.uri_to_path(uri) if found?
        end

        def server?
            uri and uri.host
        end
        
        def retrieve
            #debug 'source retrieve'
            super
        end

        def server
            (uri and uri.host) or Puppet.settings[:server]
        end

        def port
            (uri and uri.port) or Puppet.settings[:masterport]
        end
        private

        def scheme
            (uri and uri.scheme)
        end

        def uri
            @uri ||= URI.parse(URI.escape(metadata.source))
        end
    end


    # Autorequire the nearest ancestor directory found in the catalog.
    autorequire(:concat_fragment) do
        debug 'autorequire concat_file'
        #raise 'autorequire concat_file'
        req = []
        #puts 'autorequire concat_fragment on files'
        provider.register
        catalog.resources.each do |r|
            if r.is_a?(Puppet::Type.type(:concat_fragment))
                if r[:parent] == self[:name]
                    #puts 'autorequire concat_file ' + self[:name] + ' ' + r.to_s
                    req.push(r.to_s)
                end
            end
        end
        sources = self[:source]
        if sources
            #debug 'autorequire concat_fragment ' + sources.inspect
            sources = [sources] unless sources.is_a?(Array)
            sources.each do |source|
                uri = URI.parse(URI.escape(source))
                if uri.scheme == 'file'
                    path = Puppet::Util.uri_to_path(uri)

                    #debug 'autorequire concat_fragment got path ' + path.to_s
                    r = catalog.resource(:concat_file, path)
                    if r
                        req << r
                    else
                        r = catalog.resource(:file, path)
                        if r
                            req << r
                        end
                    end
                    #req.push(path)
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
