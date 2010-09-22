# Matisse - Generate web based photo albums.
# Copyright (C) 2005 Andrew Leppard <aleppard@picknowl.com.au>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# Documentation
#    perldoc matisse.pl
#
# Libraries Required
#    XML::Parser
#    XML::XPath
#    ImageMagick
#    PerlMagick

# TODO: Doc library versions.

# TODO: will probably require tidy too: HTML::Tidy not yet available!

# TODO: standardise variable naming...

# TODO: Need flag to force rebuilding images... remove action option?

# TODO: There are some centering issues with vertical photos.

# TODO: Check code validates OK.

# TODO: Use CSS for structure, not tables.

use warnings; use strict;

use Encode;
use File::Copy;
use File::Spec;
use Getopt::Long;
use Image::Magick;
use XML::XPath;
use XML::XPath::XMLParser;

my $action    = "all";
my $file_name = "album.xml";

my $default_album_template = 
  "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML//EN\">
<html>
<head>
\${HEAD}
<title>Photographs</title>
</head>
<body>
\${BODY}
</body>
</html>
";

my $default_group_template =
  "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML//EN\">
<html>
<head>
\${HEAD}
<title>\${SECTION_NAME} - \${GROUP_NAME}</title>
</head>
<body>
\${BODY}
</body>
</html>
";

my $default_photo_template =
  "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML//EN\">
<html>
<head>
\${HEAD}
<title>\${PHOTO_DESC}</title>
</head>
<body>
\${BODY}
</body>
</html>
";

# Process command line options
GetOptions("action=s" => \$action);

# TODO: Should fail if it doens't recognise an option!

if ($action ne "all" && $action ne "photos" && $action ne "pages") {
  die "Action must be one of [photos, pages, all].";
}

if ($#ARGV >= 0) {
  $file_name = $ARGV[0];
}

my $xml = XML::XPath->new(filename => $file_name);
my %album_attributes = &getAlbumAttributes($xml);

my $output_dir_name = $album_attributes{"output"};
if (!(-d "$output_dir_name")) {
  mkdir $output_dir_name;
}

$output_dir_name .= "album/";
if (!(-d "$output_dir_name")) {
  mkdir $output_dir_name;
}

if ($action eq "all" || $action eq "photos") {
  &createAlbumPhotos($xml, $output_dir_name, %album_attributes);
}

if ($action eq "all" || $action eq "pages") {
  &copyCSS($output_dir_name, %album_attributes);
  &createAlbumPages($xml, $output_dir_name, %album_attributes);
}

print "Done!\n";

sub getAlbumAttributes($) {
  my ($xml) = @_;

  my $albums = $xml->find('/album');
  my $album = ($albums->get_nodelist)[0];
  my %album_attributes = ();

  $album_attributes{"name"} =
    ($album->findvalue('@name') or "Photos");
  $album_attributes{"photos"} =
    ($album->findvalue('@photos') or "");
  $album_attributes{"output"} =
    ($album->findvalue('@output') or ".");
  $album_attributes{"css"} =
    ($album->findvalue('@css') or "");
  $album_attributes{"thumbnail_size"} =
    int($album->findvalue('@thumbnail_size') or 200);
  $album_attributes{"full_size"} =
    int($album->findvalue('@full_size') or 800);
  $album_attributes{"photos_per_line"} =
    int($album->findvalue('@photos_per_line') or 3);
  $album_attributes{"copyright"} =
    ($album->findvalue('@copyright') or "");

  # Read template pages
  if ($album->findvalue('@album_template')) {
    $album_attributes{"album_template"} =
      &readFile($album->findvalue('@album_template'));
  }
  else {
    $album_attributes{"album_template"} = $default_album_template;
  }

  if ($album->findvalue('@group_template')) {
    $album_attributes{"group_template"} =
      &readFile($album->findvalue('@group_template'));
  }
  else {
    $album_attributes{"group_template"} = $default_group_template;
  }

  if ($album->findvalue('@photo_template')) {
    $album_attributes{"photo_template"} =
      &readFile($album->findvalue('@photo_template'));
  }
  else {
    $album_attributes{"photo_template"} = $default_photo_template;
  }
      
  return %album_attributes;
}

sub readFile($) {
  my ($file_name) = @_;
  my $file_contents = "";

  open my $file, "<:utf8", $file_name
    or die "Can't open $file_name.";

  while(<$file>) {
    $file_contents .= $_;
  }

  close $file;

  return $file_contents;
}

sub createAlbumPhotos($$%) {
  my ($xml, $output_dir_name, %album_attributes) = @_;

  print "Processing Photos...\n";

  my $thumbnail_size = $album_attributes{"thumbnail_size"};
  my $full_size = $album_attributes{"full_size"};
  my $photo_root_dir_name = $album_attributes{"photos"};
  my $error;

  $output_dir_name = File::Spec->catfile($output_dir_name, "photos");
  if (!(-d $output_dir_name)) {
    mkdir $output_dir_name or die "Can't make $output_dir_name";
  }

  my $thumbnail_photo_dir_name = File::Spec->catfile($output_dir_name,
                                                     $thumbnail_size);
  my $full_photo_dir_name = File::Spec->catfile($output_dir_name,
                                                $full_size);

  if (!(-d $thumbnail_photo_dir_name)) {
    mkdir $thumbnail_photo_dir_name or
      die "Can't make $thumbnail_photo_dir_name";
  }

  if (!(-d "$full_photo_dir_name")) {
    mkdir $full_photo_dir_name or die "Can't make $full_photo_dir_name";
  }

  my $photos = $xml->find('/album/section/group/photo');

  foreach my $photo ($photos->get_nodelist) {
    my $photo_file_name = $photo->findvalue('@file');
    my $photo = new Image::Magick;

    print "$photo_file_name\n";

    my $thumbnail_file_name =
      File::Spec->catfile($thumbnail_photo_dir_name,
                          $photo_file_name);
    ensurePath($thumbnail_file_name);

    my $full_file_name = File::Spec->catfile($full_photo_dir_name,
                                             $photo_file_name);
    ensurePath($full_file_name);

    # Read photo
    my $proof_file_name = File::Spec->catfile($photo_root_dir_name,
                                              $photo_file_name);

    if (!(-f $thumbnail_file_name) || !(-f $full_file_name)) {
      $error = $photo->Read($proof_file_name);
      &dieWithImageReadError($error) if $error;
    }

    if (!(-f $thumbnail_file_name)) {
      # Create and save thumbnail version of photo
      my $thumbnail_photo = $photo->Clone();
      $thumbnail_photo = &resizePhoto($thumbnail_photo, $thumbnail_size);
      $thumbnail_photo = &retouchPhoto($thumbnail_photo);
      $error = $thumbnail_photo->Write($thumbnail_file_name);
      &dieWithImageWriteError($error) if $error;
    }      

    if (!(-f $full_file_name)) {
      # Create and save full version of photo
      $photo = &resizePhoto($photo, $full_size);
      $photo = &retouchPhoto($photo);
      $photo = &applyPhotoCopyright($photo);
      $error = $photo->Write($full_file_name);
      &dieWithImageWriteError($error) if $error;
    }
  }
}

sub copyCSS($$) {
  my ($output_dir_name, %album_attributes) = @_;

  # TODO: Perhaps offer the ability to link to an external CSS?
  if ($album_attributes{"css"} ne "") {
    my $source = $album_attributes{"css"};
    my $destination = File::Spec->catfile($output_dir_name, "stylesheet.css");

    copy($source, $destination) or die "Can't create $destination";
  }
}

sub createAlbumPages($$%) {
  my ($xml, $output_dir_name, %album_attributes) = @_;

  print "Creating pages...\n";

  my $pages_dir_name = File::Spec->catfile($output_dir_name, "pages");
  my $album_file_name = File::Spec->catfile($output_dir_name, "album.html");

  if (!(-d $pages_dir_name)) {
    mkdir $pages_dir_name or die "Can't make $pages_dir_name";
  }

  my $thumbnail_size = $album_attributes{"thumbnail_size"};
  my $full_size = $album_attributes{"full_size"};
  my $photos_per_line = $album_attributes{"photos_per_line"};

  my $photo_root_dir_name = File::Spec->catfile($output_dir_name, "photos");
  $photo_root_dir_name = File::Spec->catfile($photo_root_dir_name,
                                             $thumbnail_size);
  
  my $last_group_url = "";

  my $albums = $xml->find('/album');
  my $album = ($albums->get_nodelist)[0];
  my $sections = $album->find('/album/section');

  # Set content type and reference style sheet
  my $album_head = "<meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\">\n";
  $album_head .= "<link rel=\"stylesheet\" href=\"stylesheet.css\" type=\"text/css\"/>\n";
  
  my $album_body = "<div class=album>\n";

  foreach my $section ($sections->get_nodelist) {
    my $section_name = $section->findvalue('@name');
    
    print "$section_name\n";
    
    $album_body .= "<h2>$section_name</h2>";
    $album_body .= "<table border=0 cellspacing=0 cellpadding=6>";
    $album_body .= "<tr>";
    
    my $groups = $section->find('group');
    my @group_nodes = $groups->get_nodelist();
    
    for(my $i = 0; $i < scalar(@group_nodes); $i++) {
      my $group = $group_nodes[$i];

      if(!($i % $photos_per_line) && $i > 0) {
        $album_body .= "</tr><tr>\n";
      }
      
      $album_body .= "<td align=center>\n";
      
      my $photo_url = File::Spec->catfile("photos",
                                          $thumbnail_size,
                                          $group->findvalue('@file'));
      my $photo_file = File::Spec->catfile($photo_root_dir_name,
                                           $group->findvalue('@file'));

      my $group_name = $group->findvalue('@name');
      my $group_url = &textToURL($section_name . "_" . $group_name);
                        
      my $next_group_url = "";
      if ($i < (scalar(@group_nodes) - 1)) {
        my $next_group = $group_nodes[$i + 1];
        my $next_group_name = $next_group->findvalue('@name');
        $next_group_url = &textToURL($section_name . "_" .
                                     $next_group_name);
      }
      
      $album_body .= &writePhoto(File::Spec->catfile("pages/", $group_url),
                                 $photo_file, $photo_url);
                                
      &writeGroupPage($output_dir_name, $section_name, $group,
                      $last_group_url, $next_group_url, %album_attributes);
      
      $album_body .= "$group_name\n";

      $album_body .= "</td>\n";
      
      $last_group_url = $group_url;
    }
    
    $album_body .= "</tr>";
    $album_body .= "</table>";
  }

  $album_body .= "</div>\n";

  # Perform substitutions
  my $album_page = $album_attributes{"album_template"};

  # TODO: Put substitution into a separate function
  $album_page =~ s/\$\{HEAD\}/$album_head/e;
  $album_page =~ s/\$\{BODY\}/$album_body/e;

  # Write album page file
  open my $album_file, ">:utf8", $album_file_name
    or die "Can't open $album_file_name.";
  print $album_file $album_page;
  close $album_file;
}

sub writeGroupPage($$$$%) {
  my ($output_dir_name, $section_name, $group, $last_group_url,
      $next_group_url, %album_attributes) = @_;

  my $thumbnail_size = $album_attributes{"thumbnail_size"};
  my $full_size = $album_attributes{"full_size"};
  my $photos_per_line = $album_attributes{"photos_per_line"};

  my $full_photo_root_dir_name = 
    File::Spec->catfile($output_dir_name, "photos");
  $full_photo_root_dir_name =
    File::Spec->catfile($full_photo_root_dir_name,
                        $full_size);

  my $thumbnail_photo_root_dir_name =
    File::Spec->catfile($output_dir_name, "photos");
  $thumbnail_photo_root_dir_name =
    File::Spec->catfile($thumbnail_photo_root_dir_name,
                        $thumbnail_size);

  my $group_name = $group->findvalue('@name');

  # TODO: Put these in a hierarchy, not a single directory.
  my $this_page_url = &textToURL($section_name . "_" . $group_name);
  my $page_file_url =
    File::Spec->catfile("pages/", $this_page_url);
  my $page_file_name =
    File::Spec->catfile($output_dir_name, $page_file_url);

  # Set content type and reference style sheet
  my $group_head = "<meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\">\n";

  $group_head .= "<link rel=\"stylesheet\" href=\"../stylesheet.css\" type=\"text/css\"/>\n";

  my $group_body = "<div class=album>\n";

  $group_body .= "<h2>$section_name - $group_name</h2>";
  $group_body .= "<table border=0 cellspacing=0 cellpadding=6>";
  $group_body .= "<tr>";

  my $photos = $group->find('photo');
  my @photo_nodes = $photos->get_nodelist();

  my $last_page_url = "";

  for(my $i = 0; $i < scalar(@photo_nodes); $i++) {
    my $photo = $photo_nodes[$i];

    if(!($i % $photos_per_line) && $i > 0) {
      $group_body .= "</tr><tr>\n";
    }

    $group_body .= "<td align=center>\n";    

    my $thumbnail_photo_url = File::Spec->catfile("../photos",
                                                  $thumbnail_size,
                                                  $photo->findvalue('@file'));
    my $full_photo_url = File::Spec->catfile("../photos",
                                             $full_size,
                                             $photo->findvalue('@file'));
    my $full_photo_file =
      File::Spec->catfile($full_photo_root_dir_name,
                          $photo->findvalue('@file'));
    
    my $thumbnail_photo_file =
      File::Spec->catfile($thumbnail_photo_root_dir_name,
                          $photo->findvalue('@file'));

    my $photo_page_url = &getPhotoPageURL($photo->findvalue('@file'));
    my $photo_description = $photo->findvalue('@desc');

    $group_body .= &writePhoto($photo_page_url, $thumbnail_photo_file,
                               $thumbnail_photo_url);

    my $next_page_url = "";

    if ($i < (scalar(@photo_nodes) - 1)) {
      my $next_photo = $photo_nodes[$i + 1];
      $next_page_url = &getPhotoPageURL($next_photo->findvalue('@file'));      
    }

    &writePhotoPage($output_dir_name, $section_name, $group_name,
                    $this_page_url, $last_page_url, $photo_page_url,
                    $next_page_url, $full_photo_url, $full_photo_file,
                    $photo_description, %album_attributes);

    $group_body .= "</td>\n";

    $last_page_url = $photo_page_url;
  }

  $group_body .= "</tr>";
  $group_body .= "</table>";

  # TODO: is write the best name now that they are returning HTML?
  $group_body .= &writeNavigatorControls($last_group_url, "../album.html",
                                         $next_group_url);

  $group_body .= "</div>\n";

  # Perform substitutions
  my $group_page = $album_attributes{"group_template"};

  # TODO: Put substitution into a separate function
  $group_page =~ s/\$\{HEAD\}/$group_head/e;
  $group_page =~ s/\$\{BODY\}/$group_body/e;
  $group_page =~ s/\$\{GROUP_NAME\}/$group_name/e;
  $group_page =~ s/\$\{SECTION_NAME\}/$section_name/e;

  # Write the group page file
  open my $group_file, ">:utf8", $page_file_name
    or die "Can't open $page_file_name.";
  print $group_file $group_page;
  close $group_file;
}

sub getPhotoPageURL($) {
  my ($photo_file_name) = @_;

  # Remove image extension (if any)
  $photo_file_name =~ s/\..*$//;

  # Replace forward/backslashes with underscores
  $photo_file_name =~ s/[\/\\]/_/g;

  return &textToURL($photo_file_name);
}

sub writePhotoPage($$$$%) {
  my ($output_dir_name, $section_name, $group_name, $top_page_url,
      $last_page_url, $photo_page_url, $next_page_url,
      $photo_url, $photo_file_name, $photo_description,
      %album_attributes) = @_;

  # Get width and height of images. We want to include the the size in the
  # web page to help the browser format the page before the image is
  # downloaded.
  my $photo = new Image::Magick;
  my $error = $photo->Read($photo_file_name);  
  &dieWithImageReadError($error) if $error;

  my $width  = $photo->Get('width');
  my $height = $photo->Get('height');
  
  my $photo_page_file_name =
    File::Spec->catfile($output_dir_name, "pages/", $photo_page_url);

  # Set content type and reference style sheet
  my $photo_page_head = "<meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\">\n";
  $photo_page_head .= "<link rel=\"stylesheet\" href=\"../stylesheet.css\" type=\"text/css\"/>\n";

  my $photo_page_body = "<div class=album>\n";

  $photo_page_body .= "<center>\n";
  $photo_page_body .= "<table>\n";
  $photo_page_body .= "<tr>\n";
  $photo_page_body .= "<td>\n";
  $photo_page_body .= "<h2>$section_name - $group_name</h2>\n";
  $photo_page_body .= "<img border=2 src=\"$photo_url\" width=$width height=$height/>\n";
  $photo_page_body .= "</td>\n";
  $photo_page_body .= "</tr>\n";
  $photo_page_body .= "</table>\n";
  $photo_page_body .= "<p><i>$photo_description</i></p>\n";

  $photo_page_body .= &writeNavigatorControls($last_page_url, $top_page_url,
                                              $next_page_url);

  $photo_page_body .= "</center>\n";
  $photo_page_body .= "</div>\n";

  # Perform substitutions
  my $photo_page = $album_attributes{"photo_template"};

  # TODO: Put substitution into a separate function
  $photo_page =~ s/\$\{HEAD\}/$photo_page_head/e;
  $photo_page =~ s/\$\{BODY\}/$photo_page_body/e;
  $photo_page =~ s/\$\{GROUP_NAME\}/$group_name/e;
  $photo_page =~ s/\$\{SECTION_NAME\}/$section_name/e;
  $photo_page =~ s/\$\{PHOTO_DESC\}/$photo_description/e;

  # Write the photo page file
  open my $photo_page_file, ">:utf8", $photo_page_file_name
    or die "Can't open $photo_page_file_name.";
  print $photo_page_file $photo_page;
  close $photo_page_file;
}

# TODO: Rename to createNavigatorControlHTML?
sub writeNavigatorControls($$$) {
  my ($previous_url, $top_url, $next_url) = @_;

  my $text = "<center>\n";

  if($previous_url ne "") {
    $text .= "<a href=\"$previous_url\">« previous</a> |\n";
  }

  $text .= "<a href=\"$top_url\">top</a>";
  
  if($next_url ne "") {
    $text .= " | <a href=\"$next_url\">next »</a>\n";
  }

  $text .= "</center>\n";

  return $text;
}

# TODO: rename to createPhotoHTML?
sub writePhoto($$) {
  my ($photo_page_url, $photo_file_name, $photo_url) = @_;

  # Get width and height of images. We need this to determine whether
  # to lay out a horizontal or vertical photo. We also want to include
  # the size in the web page to help the browser format the page
  # before all the images are downloaded.
  my $photo = new Image::Magick;
  my $error = $photo->Read($photo_file_name);  
  &dieWithImageReadError($error) if $error;

  my $width  = $photo->Get('width');
  my $height = $photo->Get('height');

  if ($width > $height) {
    return &writeHorizontalPhoto($photo_page_url, $photo_url, $width, $height);
  }
  else {
    return &writeVerticalPhoto($photo_page_url, $photo_url, $width, $height);
  }
}

sub writeHorizontalPhoto($$$$$) {
  my ($photo_page_url, $photo_url, $width, $height) = @_;

  my $text = "";

  $text .= "<table class=photoframe cellspacing=10 cellpadding=0>\n";
  $text .= "<tr><td></td></tr>\n";
  $text .= "<tr>\n";
  $text .= "<td>\n";
  $text .= "<a href=\"$photo_page_url\">\n";
  $text .= "<img border=2 src=\"$photo_url\" width=$width height=$height>\n";
  $text .= "</a>\n";
  $text .= "</td>\n";
  $text .= "</tr>\n";
  $text .= "<tr><td></td></tr>\n";
  $text .= "</table>\n";

  return $text;
}

sub writeVerticalPhoto($$$$$) {
  my ($photo_page_url, $photo_url, $width, $height) = @_;

  my $text = "";

  $text .= "<table class=photoframe cellspacing=10 cellpadding=0>\n";
  $text .= "<tr>\n";
  $text .= "<td width=1></td>\n";
  $text .= "<td>\n";
  $text .= "<a href=\"$photo_page_url\">\n";
  $text .= "<img border=2 src=\"$photo_url\" width=$width height=$height>\n";
  $text .= "</a>\n";
  $text .= "</td>\n";
  $text .= "<td width=1></td>\n";
  $text .= "</tr>\n";
  $text .= "</table>\n";

  return $text;
}

# TODO: Find a package that does this for us!
sub textToURL($) {
  my ($text) = @_;

  # Remove any unicode from HTML file names / links. Unicode isn't
  # universally supported here and can cause problems.
  $text = encode("iso-8859-1", $text);

  # Replace all spaces with underscores
  $text =~ s/ /_/g;
  
  # Replace all punctuation with "_" just to be safe.
  $text =~ s/[[:punct:]]/_/g;

  # Replace any multiple underscores with one.
  $text =~ s/_{2,}/_/g;

  $text =~ tr/A-Z/a-z/;
  $text .= ".html";

  return $text;
}

sub dieWithImageReadError($) {
  my ($error) = @_;

  die "$error\nError reading image";
}

sub dieWithImageWriteError($) {
  my ($error) = @_;

  die "$error\nError writing image";
}

sub ensurePath($) {
  my ($full_path) = @_;

  my @directories = File::Spec->splitdir($full_path);
  my $path = "";

  # Remove the file name from the list of directories
  pop @directories;

  foreach my $directory (@directories) {

    # For some reason on absolute paths it returns "" first
    if ($directory eq "") {
      $path = "/";
    }
    else {
      # Build path
      if ($path ne "") {
        $path = File::Spec->catdir($path, $directory);
      }
      else {
        $path = $directory;
      }
      
      # Create directory if it doesn't already exist
      if (!(-d $path)) {
        mkdir $path or die "Can't make $path";
      }
    }
  }
}

sub resizePhoto($$) {
  my ($photo, $new_size) = @_;

  my $old_width  = $photo->Get('width');
  my $old_height = $photo->Get('height');

  my $aspect_ratio = $old_width / $old_height;
  my $new_width;
  my $new_height;

  # Photo is horizontal. Set the width to the given size.
  if ($old_width > $old_height) {
    $new_width = $new_size;
    $new_height = $new_size / $aspect_ratio;
  }

  # Photo is vertical (or square). Set the height to the given size.
  else {
    $new_height = $new_size; 
    $new_width = $new_size * $aspect_ratio;
  }
    
  $photo->Resize(width => $new_width, height => $new_height);
  $photo->Crop(width => $new_width, height => $new_height);

  return $photo;
}

sub retouchPhoto($) {
  my ($photo) = @_;

  # TODO: Call function to remove scratches, dust etc?
  return $photo;
}

sub applyPhotoCopyright($) {
  my ($photo) = @_;

  # TODO: Print a small copyright message on the photo
  return $photo;
}

1;
__END__

=head1 NAME

matisee.pl - Generate web based photo albums.

=head1 PREFACE

This programme generates a web based photo album which can be used
to display a collection of photos on the web. It takes an album
description file and repository of photos and creates all the necessary
HTML code which can be displayed on the web.

=head2 ARGUMENTS

=over 2

=item C<-action>

=back

=cut

=head1 AUTHOR

 Andrew Leppard <aleppard@picknowl.com.au>

=head1 COPYRIGHT

Copyright (C) Andrew Leppard 2005. All rights reserved.

=cut
