// +----------------------------------------------------------------------
// | Project : ray.
// | All rights reserved.
// +----------------------------------------------------------------------
// | Copyright (c) 2013-2015.
// +----------------------------------------------------------------------
// | * Redistribution and use of this software in source and binary forms,
// |   with or without modification, are permitted provided that the following
// |   conditions are met:
// |
// | * Redistributions of source code must retain the above
// |   copyright notice, this list of conditions and the
// |   following disclaimer.
// |
// | * Redistributions in binary form must reproduce the above
// |   copyright notice, this list of conditions and the
// |   following disclaimer in the documentation and/or other
// |   materials provided with the distribution.
// |
// | * Neither the name of the ray team, nor the names of its
// |   contributors may be used to endorse or promote products
// |   derived from this software without specific prior
// |   written permission of the ray team.
// |
// | THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// | "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// | LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// | A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// | OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// | SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// | LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// | DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// | THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// | (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// | OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// +----------------------------------------------------------------------

#include <tools/Rtti.h>
#include <tools/RttiFactory.h>
#include <cassert>

using namespace rtti;

__ImplementClass(Interface, "RTTI")

// Global variable initialization order is undfined.
// So, make sure to use it after initialization

Rtti::Rtti(const std::string& name, RttiConstruct creator, const Rtti* parent) noexcept
	: _name(name)
	, _parent(parent)
	, _construct(creator)
{
	Factory::instance()->add(this);
}

Rtti::~Rtti() noexcept
{
}

const Rtti*
rtti::Rtti::getParent() const noexcept
{
    return _parent;
}

bool
Rtti::isDerivedFrom(const Rtti* other) const
{
	assert(other);

	for (const Rtti* cur = this; cur != 0; cur = cur->getParent())
	{
		if (cur == other)
		{
			return true;
		}
	}

	return false;
}

bool
Rtti::isDerivedFrom(const Rtti& other) const
{
	return this->isDerivedFrom(&other);
}

bool
Rtti::isDerivedFrom(const std::string& name) const
{
	for (const Rtti* cur = this; cur != 0; cur = cur->getParent())
	{
		if (cur->_name == name)
		{
			return true;
		}
	}

	return false;
}


Interface::Interface() noexcept
{
}

Interface::~Interface() noexcept
{
}

bool
Interface::isA(const Rtti* rtti) const noexcept
{
	return this->rtti()->isDerivedFrom(rtti);
}

bool
Interface::isA(const Rtti& rtti) const noexcept
{
	return this->rtti()->isDerivedFrom(rtti);
}

bool
Interface::isA(const std::string& rttiName) const noexcept
{
	return this->rtti()->isDerivedFrom(rttiName);
}

