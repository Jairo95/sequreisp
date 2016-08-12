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

class Api::ApplyChangesController < Api::ApiController
  permissions :apply_changes
  # GET /clients
  # GET /clients.xml
  def apply_changes
    errors = Configuration.first.apply_changes
    respond_to do |format|
      if errors.empty?
        format.json  { head :ok }
      else
        format.json  { render :json => errors, :status => :conflict }
      end
    end
  end
end
