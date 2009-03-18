

module MarcHelper

  # Takes an array of ruby MARC objects, adds ServiceResponses
  # for the 856 links contained. 
  # Returns a hash of arrays of ServiceResponse objects added, keyed
  # by service type value string. 
  def add_856_links(request, marc_records, options = {})
    options[:default_service_type] ||= "fulltext_title_level"
    options[:match_reliability] ||= ServiceResponse::MatchExact

    responses_added = Hash.new
    
    # Keep track of urls to avoid putting the exact same url in twice
    urls_seen = Array.new
    
    marc_records.each do |marc_xml|      
      marc_xml.find_all {|f| '856' === f.tag}.each do |field|
        url = field['u']

        # No u field? Forget it.
        next if url.nil?

        # Already got it from another catalog record?
        next if urls_seen.include?(url)

        # If this is a journal, don't add the URL if it matches in our
        # SFXUrl finder, because that means we think it's an SFX controlled
        # URL. But if it's not a journal, use it anyway, because it's probably
        # an e-book that is not in SFX, even if it's from a vendor who is in
        # SFX. We use MARC leader byte 7 to tell. Confusing enough?
        is_journal = (marc_xml.leader[7,1] == 's')
        next if  is_journal && (SfxUrl.sfx_controls_url?(url))
        # TO DO: Configure suppress urls in SfxUrl. 
        
        urls_seen.push(url)
        
        
        display_name = nil
        if field['y']
          display_name = field['y']
        else
          # okay let's try taking just the domain from the url
          begin
            u_obj = URI::parse( url )
            display_name = u_obj.host
          rescue Exception
          end
          # Okay, can't parse out a domain, whole url then.
          display_name = url if display_name.nil?
        end
        # But if we've got a $3, the closest MARC comes to a field
        # that explains what this actually IS, use that too please.
        display_name = field['3'] + ' from ' + display_name if field['3']

        # Build the response. 
        
        response_params = {:service=>self, :display_text=>display_name, :url=>url}
        # get all those $z subfields and put em in notes.      
        response_params[:url] = url
  
        # subfield 3 is being used for OCA records loaded in our catalog.
        response_params[:notes] =
        field.subfields.collect {|f| f.value if (f.code == 'z') }.compact.join('; ')
  
        unless ( field['3'] || ! is_journal ) # subfield 3 is in fact some kind of coverage note, usually. 
          response_params[:notes] += "; " unless response_params[:notes].blank? 
          response_params[:notes] += "Dates of coverage unknown."
        end

        
        unless ( options[:match_reliability] == ServiceResponse::MatchExact )
          response_params[:match_reliability] = options[:match_reliability]

          response_params[:edition_str] = edition_statement(marc_xml)
        end

        # Figure out the right service type value for this, fulltext, ToC,
        # whatever.
        service_type_value = service_type_for_856( field, options ) 
                
        # Add the response
        response = request.add_service_response(response_params, 
            [ service_type_value  ])
        
        responses_added[service_type_value] ||= Array.new
        responses_added[service_type_value].push(response)
      end
    end
    return responses_added
  end

  # Take a ruby Marc Field object representing an 856 field,
  # decide what umlaut service type value to map it to. Fulltext, ToC, etc.
  # This is neccesarily a heuristic guess, Marc doesn't have enough granularity
  # to really let us know for sure. 
  def service_type_for_856(field, options)
    options[:default_service_type] ||= "fulltext_title_level"

    # LC records here at hopkins have "Table of contents only" in the 856$3
      # Think that's a convention from LC? 
      if (field['3'] && field['3'].downcase == "table of contents only")
        return "table_of_contents"
      elsif (field['3'] && field['3'].downcase =~ /description/)
        # If it contains the word 'description', it's probably an abstract.
        # That's the best we can do, sadly. 
        return "abstract"
      elsif ( field['u'] =~ /www\.loc\.gov/ )
        # Any other loc.gov link, we know it's not full text, don't put
        # it in full text field, put it as "see also". 
        return "highlighted_link"
      else
        return options[:default_service_type]
      end
  end

  # From a marc record, get a string useful to display for identifying
  # which edition/version of a work this represents. 
  def edition_statement(marc, options = {})
    options[:include_repro_info] ||= true

    parts = Array.new



    #250
    if ( marc['250'])
      parts.push( marc['250']['a'] ) unless marc['250']['a'].blank?
      parts.push( marc['250']['b'] ) unless marc['250']['b'].blank?
    end
    
    # 260
    if ( marc['260'])
      if (marc['260']['b'] =~ /s\.n\./)
        parts.push(marc['260']['a']) unless marc['260']['a'].blank?
      else
        parts.push(marc['260']['b']) unless marc['260']['b'].blank?
      end
      parts.push( marc['260']['c'] ) unless marc['260']['c'].blank?
    end

    #245$h GMD
    unless ( marc['245'].blank? || marc['245']['h'].blank? )
      parts.push('(' + marc['245']['h'].gsub(/[^\w\s]/, '').titlecase + ')')
    end
      
    # 533
    if options[:include_repro_info] && marc['533']
      marc['533'].subfields.each do |s|
        if ( s.code == 'a' )
          parts.push('<em>' + s.value.gsub(/[^\w\s]/, '') + '</em>:'  )  
        elsif ( s.code != '7' && s.code != 'f' && s.code != 'b')
          parts.push(s.value)
        end       
      end
    end
      
    return nil if parts.length == 0

    return parts.join(' ')
  end
  
end
