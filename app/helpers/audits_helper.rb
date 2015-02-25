# Sequreisp - Copyright 2010, 2011 Luciano Ruete
#
# This file is part of Sequreisp.
#
# Sequreisp is free software: you can redistribute it and/or modify
# it under the terms of the GNU Afero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Sequreisp is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Afero General Public License for more details.
#
# You should have received a copy of the GNU Afero General Public License
# along with Sequreisp.  If not, see <http://www.gnu.org/licenses/>.

module AuditsHelper

  def expand_changes(changes,type)
    html = ""
    html << "<ul>"
    changes.each do |key,value|
      if value.class == Array
        val = "<span style=\"text-decoration:line-through;\"> #{value[0]}</span> -> #{value[1]}"
      else
        val = value
      end
      human_attribute_name = type.constantize.send :human_attribute_name, key rescue key
      html << "<li><b>#{human_attribute_name}:</b> #{val}</li>"
    end
    html << "</ul>"
    html
  end

  def link_to_auditable(audit)
    a = nil

    a = audit.auditable.respond_to?('auditable_model_to_show') ? audit.auditable.auditable_model_to_show : audit.auditable rescue nil

    if a.nil?
      'N/A'
    else
      link_to(h(a.auditable_name), a)
    end
  end

  def collect_of_auditable_models
    Audit.audited_classes.select{|c| I18n.t("activerecord.models.#{c.name.underscore}.one", :default => "").presence }.collect{|c| [I18n.t("activerecord.models.#{c.name.underscore}.one"),c.name] }.sort
  end


  def collect_actions
    [
      [I18n.t('audits.create'),"create"],
      [I18n.t('audits.update'),"update"],
      [I18n.t('audits.destroy'),"destroy"]
    ]
  end

  def attributes_audits_to_json
    result_hash = {}
    Audit.audited_classes.each do |cl|
      next unless I18n.t("activerecord.models.#{cl.name.underscore}.one", :default => "").presence
      result_hash[cl] = [];
      cl.audited_columns.each do |a|
        result_hash[cl] << { :id => a.name,:name => I18n.t("activerecord.attributes.#{cl.name.underscore}.#{a.name}") } if I18n.t("activerecord.attributes.#{cl.name.underscore}.#{a.name}", :default => "").presence
      end
    end
    result_hash.to_json
  end
end
