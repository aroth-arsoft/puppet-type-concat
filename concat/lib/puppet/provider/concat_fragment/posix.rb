require File.dirname(__FILE__) + '/../../concat/impl'

Puppet::Type.type(:concat_fragment).provide(:posix) do
    desc "Manage concat_files on Posix systems."

    defaultfor :operatingsystem => [:debian, :ubuntu]

    mk_resource_methods

    # Provide an external hook.  Yay breaking out of APIs.
    def apply(header=nil, footer=nil, content=nil)
        #ConcatFileImpl.dump
        if resource[:ensure] == :present
            #notice "apply hdr=#{header} ftr=#{footer} cnt=#{content}"
            @fragment.set(header, footer, content)
        end
        #ConcatFileImpl.dump
    end
    
    def register
        #info "register parent=#{resource[:parent]} target=#{resource[:target]}"
        if resource[:parent] != nil
            parent = resource[:parent]
        else 
            parent = resource[:target]
        end
        @fragment = ConcatFileImpl.register_fragment(resource[:name], parent, resource[:order].to_i)
    end
end
