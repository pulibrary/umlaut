class Sfx < Service
  require 'uri'
  require 'open_url'
  def handle(request)
    client = self.initialize_client(request)
    begin
      response = self.do_request(client)
      self.parse_response(response, request)
      return request.dispatched(self, true)
    rescue Errno::ETIMEDOUT
      # Request to SFX timed out. Record this as unsuccesful in the dispatch table. 
      return request.dispatched(self, false)
    end
  end
  def initialize_client(request)
    transport = OpenURL::Transport.new(@base_url)
    context_object = request.referent.to_context_object
    context_object.referrer.set_identifier(request.referrer.identifier)if request.referrer
    transport.add_context_object(context_object)
    transport.extra_args["sfx.response_type"]="multi_obj_xml"
    @get_coverage = false
    unless context_object.referent.metadata.has_key?("issue") or context_object.referent.metadata.has_key?("volume") or context_object.referent.metadata.has_key?("date")    
      transport.extra_args["sfx.ignore_date_threshold"]="1"
      transport.extra_args["sfx.show_availability"]="1"
      @get_coverage = true
    end  
    if context_object.referent.identifier and context_object.referent.identifier.match(/^info:doi\//)
      transport.extra_args['sfx.doi_url']='http://dx.doi.org'
    end
    return transport
  end
  
  def do_request(client)
    client.transport_inline
    return client.response
  end
  
  def parse_response(resolver_response, request)
    require 'hpricot'
    require 'cgi'
    doc = Hpricot(resolver_response)     
    # parse perl_data from response
    related_items = []
    attr_xml = CGI.unescapeHTML((doc/"/ctx_obj_set/ctx_obj/ctx_obj_attributes").inner_html)
    perl_data = Hpricot(attr_xml)
    (perl_data/"//hash/item[@key='@sfx.related_object_ids']").each { | rel | 
      (rel/'/array/item').each { | item | 
        related_items << item.inner_html
      } 
    }

    object_id_node = (perl_data/"//hash/item[@key='rft.object_id']")
    object_id = nil
    if object_id_node
      object_id = object_id_node.inner_html
    end
    metadata = request.referent.metadata
    if request.referent.format == 'journal'
      unless metadata["jtitle"]
        jtitle_node = (perl_data/"//hash/item[@key='rft.jtitle']")
        if jtitle_node
          request.referent.enhance_referent('jtitle', jtitle_node.inner_html) 
        end
      end
    end
    if request.referent.format == 'book'
      unless metadata["btitle"]
        btitle_node = (perl_data/"//hash/item[@key='rft.btitle']")
        if btitle_node
          request.referent.enhance_referent('btitle', btitle_node.inner_html) 
        end
      end
    end    
    issn_node = (perl_data/"//hash/item[@key='rft.issn']")
    if issn_node
      unless metadata['issn'] 
        request.referent.enhance_referent('issn', issn_node.inner_html)
      end
    end    
    eissn_node = (perl_data/"//hash/item[@key='rft.eissn']")
    if eissn_node
      unless metadata['eissn'] 
        request.referent.enhance_referent('eissn', eissn_node.inner_html)
      end
    end      
    isbn_node = (perl_data/"//hash/item[@key='rft.isbn']")
    if isbn_node
      unless metadata['isbn'] 
        request.referent.enhance_referent('isbn', isbn_node.inner_html)
      end
    end  
    genre_node = (perl_data/"//hash/item[@key='rft.genre']")
    if genre_node 
      unless metadata['genre']
        request.referent.enhance_referent('genre', genre_node.inner_html)
      end
    end    
    
    issue_node = (perl_data/"//hash/item[@key='rft.issue']")
    if issue_node 
      unless metadata['issue']
        request.referent.enhance_referent('issue', issue_node.inner_html)
      end
    end      
    vol_node = (perl_data/"//hash/item[@key='rft.volume']")
    if vol_node 
      unless metadata['volume']
        request.referent.enhance_referent('volume', vol_node.inner_html)
      end
    end      

    request_id = nil
    request_id_node = (perl_data/"//hash/item[@key='sfx.request_id']") 
    if request_id_node
      request_id = request_id_node.inner_html
    end    

    if object_id
      journal = Journal.find_by_object_id(object_id)
    elsif request.referent.metadata['issn']
      journal = Journal.find_by_issn_or_eissn(request.referent.metadata['issn'], request.referent.metadata['issn'])
    end  
    if journal
      journal.categories.each do | category |
        request.add_service_response({:service=>self,:key=>'SFX',:value_string=>category.category,:value_text=>category.subcategory},['subject'])
      end
    end
    (doc/"/ctx_obj_set/ctx_obj/ctx_obj_targets/target").each do|target|  
      if (target/"/displayer")
        source = "SFX/"+(target/"/displayer").inner_html
      else
        source = "SFX"+URI.parse(self.url).path
      end    
      if (target/"/service_type").inner_html == "getFullTxt" 
        coverage = ''
        if @get_coverage
          if journal 
            cvg = journal.coverages.find(:first, :conditions=>['provider = ?', (target/"/target_public_name").inner_html])
            coverage = cvg.coverage if cvg
          end
        end
        value_text = {
          :url=>CGI.unescapeHTML((target/"/target_url").inner_html),
          :note=>CGI.unescapeHTML((target/"/note").inner_html),
          :source=>source,
          :coverage=>coverage
        }   
        request.add_service_response({:service=>self,:key=>(target/"/target_public_name").inner_html,:value_string=>(target/"/target_service_id").inner_html,:value_text=>value_text.to_yaml},['fulltext'])

      elsif (target/"/service_type").inner_html == "getDocumentDelivery"
        value_text = {
          :url=>CGI.unescapeHTML((target/"/target_url").inner_html),
          :note=>CGI.unescapeHTML((target/"/note").inner_html),
          :source=>source
        }
        request.add_service_response({:service=>self,:key=>(target/"/target_public_name").inner_html,:value_string=>request_id,:value_text=>value_text.to_yaml},['document_delivery'])
      end    
    end   
  end
  
  def to_fulltext(response)  
    value_text = YAML.load(response.value_text)     
    return {:display_text=>response.response_key, :note=>value_text[:note],:coverage=>value_text[:coverage],:source=>value_text[:source]}
  end
  def response_to_view_data(response)
    # default for any type, same as to_fulltext
    return to_fulltext(response)
  end
  

  
  def response_url(response)
    txt = YAML.load(response.value_text)
    return CGI.unescapeHTML(txt[:url])
  end
end
