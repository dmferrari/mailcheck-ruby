require 'logger'
require 'mailcheck/version'
require 'mailcheck/domains'
require 'mailcheck/tlds'

class Mailcheck
  THRESHOLD = 3

  def initialize(opts = {})
    @domains = opts[:domains] || DOMAINS
    @top_level_domains = opts[:top_level_domains] || TOP_LEVEL_DOMAINS
    @threshold = opts[:threshold] || THRESHOLD
  end

  def suggest(email)
    email_parts = split_email(email.downcase)
    return false unless email_parts

    email_parts[:top_level_domain] = replace_known_misspelled_domains(email_parts[:top_level_domain])
    closest_domain = find_closest_domain(email_parts[:domain], @domains)
    if closest_domain
      if closest_domain != email_parts[:domain]
        # The email address closely matches one of the supplied domains return a suggestion
        suggested_email = "#{email_parts[:address]}@#{closest_domain}"
        Mailcheck.logger.info "Email address suggested - Original: #{email} - Suggested: #{suggested_email}"
        return { address: email_parts[:address], domain: closest_domain, full: suggested_email }
      end
    else
      # The email address does not closely match one of the supplied domains
      closest_top_level_domain = find_closest_domain(email_parts[:top_level_domain], @top_level_domains)
      if email_parts[:domain] && closest_top_level_domain && closest_top_level_domain != email_parts[:top_level_domain]
        # The email address may have a mispelled top-level domain return a suggestion
        domain = email_parts[:domain]
        closest_domain = closest_domain_for(email_parts, domain, closest_top_level_domain)
        suggested_email = "#{email_parts[:address]}@#{closest_domain}"
        Mailcheck.logger.info "Email address suggested - Original: #{email} - Suggested: #{suggested_email}"
        return { address: email_parts[:address], domain: closest_domain, full: suggested_email }
      end
    end
    # The email address exactly matches one of the supplied domains, does not closely
    # match any domain and does not appear to simply have a mispelled top-level domain,
    # or is an invalid email address do not return a suggestion.
    false
  end

  private

  def find_closest_domain(domain, domains)
    min_dist = 99
    closest_domain = nil
    return nil if domains.nil? || domains.empty?

    domains.each do |dmn|
      return domain if domain == dmn

      dist = sift_3distance(domain, dmn)
      if dist < min_dist
        min_dist = dist
        closest_domain = dmn
      end
    end
    closest_domain if min_dist <= @threshold && closest_domain
  end

  def sift_3distance(s1, s2)
    # sift3: http:#siderite.blogspot.com/2007/04/super-fast-and-accurate-string-distance.html
    c = lcs = offset1 = offset2 = 0
    max_offset = 5
    while (c + offset1 < s1.length) && (c + offset2 < s2.length)
      if s1[c + offset1] == s2[c + offset2]
        lcs += 1
      else
        offset1 = offset2 = 0
        max_offset.times do |i|
          if c + i < s1.length && s1[c + i] == s2[c]
            offset1 = i
            break
          end
          if c + i < s2.length && s1[c] == s2[c + i]
            offset2 = i
            break
          end
        end
      end
      c += 1
    end
    (s1.length + s2.length) / 2.0 - lcs
  end

  def split_email(email)
    parts = email.split('@')
    return false if parts.length < 2 || parts.any? { |p| p == '' }

    domain = parts.pop
    domain_parts = domain.split('.')
    return false if domain_parts.empty?

    {
      top_level_domain: domain_parts[1..-1].join('.'),
      domain: domain,
      address: parts.first
    }
  end

  def closest_domain_for(email_parts, domain, closest_top_level_domain)
    if email_parts[:top_level_domain].empty?
      "#{domain}.#{closest_top_level_domain}"
    else
      domain.sub(/#{email_parts[:top_level_domain]}$/, closest_top_level_domain)
    end
  end

  def replace_known_misspelled_domains(domain)
    case domain
    when 'gmail.net'
      'gmail.com'
    when 'att.com'
      'att.net'
    else
      domain
    end
  end

  class << self
    attr_writer :logger
    def logger
      @logger ||= Logger.new($stdout).tap do |log|
        log.progname = name
      end
    end
  end
end
